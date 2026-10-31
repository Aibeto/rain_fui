/*
 * rain_fui — main-thread facade for the bundled FFmpeg WebAssembly build.
 *
 * Contract consumed by lib/src/ffmpeg/ffmpeg_web.dart (dart:js_interop):
 *
 *   window.rainFfmpeg = {
 *     init(): Promise<{ok, version, error}>,
 *     run(args: string[], onLine: (stream, line) => void):
 *       Promise<{exitCode, stdout, stderr}>,
 *     cancel(): void,
 *     download(virtualPath: string, downloadName: string): void,
 *   };
 *
 * All the heavy lifting happens in ffmpeg_worker.js so the UI thread never
 * blocks. A fresh Emscripten instance is used per run: FFmpeg calls exit(),
 * which leaves the module unusable.
 */
(function () {
  'use strict';

  var WORKER_URL = 'ffmpeg/ffmpeg_worker.js';

  var worker = null;
  var nextId = 1;
  var pending = new Map();

  function workerUrl() {
    // Respects <base href> when the app is served from a sub-path.
    return new URL(WORKER_URL, document.baseURI).href;
  }

  // The threaded wasm core needs SharedArrayBuffer, i.e. a cross-origin
  // isolated document. Say so instead of surfacing a bare wasm failure.
  function isolationHint() {
    if (typeof SharedArrayBuffer !== 'undefined' && self.crossOriginIsolated !== false) return '';
    return (
      ' — FFmpeg needs cross-origin isolation (send Cross-Origin-Opener-Policy: same-origin ' +
      'and Cross-Origin-Embedder-Policy: require-corp) so that SharedArrayBuffer exists'
    );
  }

  function terminate() {
    if (worker) {
      worker.terminate();
      worker = null;
    }
    pending.clear();
  }

  function settle(id, handler) {
    var entry = pending.get(id);
    if (!entry) return;
    pending.delete(id);
    handler(entry);
  }

  function ensureWorker() {
    if (worker) return worker;
    worker = new Worker(workerUrl());
    worker.onmessage = function (event) {
      var message = event.data || {};
      if (message.type === 'line') {
        var entry = pending.get(message.id);
        if (entry && entry.onLine) {
          try {
            entry.onLine(message.stream, message.line);
          } catch (error) {
            console.error('rainFfmpeg: onLine handler threw', error);
          }
        }
        return;
      }
      settle(message.id, function (entry) {
        if (message.type === 'done') {
          entry.resolve({
            exitCode: message.exitCode | 0,
            stdout: message.stdout || '',
            stderr: message.stderr || '',
          });
        } else if (message.type === 'init') {
          entry.resolve({
            ok: !!message.ok,
            version: message.version || '',
            error: message.error || '',
          });
        } else if (message.type === 'file') {
          entry.resolve({ name: message.name || '', bytes: message.bytes });
        } else {
          entry.reject(new Error(message.message || 'FFmpeg worker failure'));
        }
      });
    };
    worker.onerror = function (event) {
      var text = (event && event.message) || 'FFmpeg worker failed to start';
      var entries = Array.from(pending.values());
      terminate();
      entries.forEach(function (entry) {
        entry.reject(new Error(text));
      });
    };
    return worker;
  }

  window.rainFfmpeg = {
    init: function () {
      return new Promise(function (resolve) {
        var target;
        try {
          target = ensureWorker();
        } catch (error) {
          resolve({
            ok: false,
            version: '',
            error: String((error && error.message) || error) + isolationHint(),
          });
          return;
        }
        var id = nextId++;
        pending.set(id, {
          resolve: function (result) {
            var ok = !!result.ok;
            resolve({
              ok: ok,
              version: result.version || '',
              error: ok ? '' : (result.error || 'FFmpeg wasm failed to initialise') + isolationHint(),
            });
          },
          reject: function (error) {
            resolve({
              ok: false,
              version: '',
              error: String((error && error.message) || error) + isolationHint(),
            });
          },
        });
        target.postMessage({ id: id, type: 'init' });
      });
    },

    run: function (args, onLine) {
      return new Promise(function (resolve, reject) {
        var target;
        try {
          target = ensureWorker();
        } catch (error) {
          reject(error);
          return;
        }
        var id = nextId++;
        pending.set(id, { resolve: resolve, reject: reject, onLine: onLine });
        try {
          target.postMessage({ id: id, type: 'run', args: Array.from(args || [], String) });
        } catch (error) {
          pending.delete(id);
          reject(error);
        }
      });
    },

    cancel: function () {
      // A wasm FFmpeg cannot be signalled, so the only stop is tearing the
      // worker down. The next run boots a clean one.
      terminate();
    },

    download: function (virtualPath, downloadName) {
      var target = worker;
      if (!target) {
        console.warn('rainFfmpeg: no active worker, cannot read ' + virtualPath);
        return;
      }
      var id = nextId++;
      pending.set(id, {
        resolve: function (result) {
          var blob = new Blob([result.bytes], { type: 'application/octet-stream' });
          var url = URL.createObjectURL(blob);
          var anchor = document.createElement('a');
          anchor.href = url;
          anchor.download = downloadName || String(virtualPath).split('/').pop() || 'output';
          document.body.appendChild(anchor);
          anchor.click();
          anchor.remove();
          setTimeout(function () {
            URL.revokeObjectURL(url);
          }, 30000);
        },
        reject: function (error) {
          console.error('rainFfmpeg: download failed', error);
        },
      });
      target.postMessage({ id: id, type: 'read', path: String(virtualPath) });
    },
  };
})();
