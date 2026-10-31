/*
 * rain_fui — FFmpeg WebAssembly worker.
 *
 * Loads the Emscripten build produced by scripts/ffmpeg/build-web.sh
 * (ffmpeg.js + ffmpeg.wasm, single-threaded, MODULARIZE/EXPORT_NAME=createFFmpegCore)
 * and runs one fresh module instance per request, because FFmpeg calls exit()
 * and an exited module cannot be reused.
 *
 * Protocol (see ffmpeg_bridge.js):
 *   in : {id, type: 'init'}
 *   in : {id, type: 'run', args: string[]}
 *   in : {id, type: 'read', path: string}
 *   out: {id, type: 'init', ok, version, error}
 *   out: {id, type: 'line', stream: 'stdout'|'stderr', line}
 *   out: {id, type: 'done', exitCode, stdout, stderr}
 *   out: {id, type: 'file', name, bytes: ArrayBuffer}
 *   out: {id, type: 'error', message}
 */
'use strict';

var CORE_SCRIPT = 'ffmpeg.js';

// The core is built with pthreads, so Emscripten both (a) needs a worker script
// to host each thread and (b) derives that script from `self.location.href`.
// Because this file *is* the worker URL, Emscripten spawns threads by loading
// this wrapper again with `name === 'em-pthread'`. In that role we must not
// install our own message handler: evaluate the core and let it take over,
// exactly as if ffmpeg.js had been the worker entry point.
if (self.name === 'em-pthread') {
  importScripts(CORE_SCRIPT);
} else {

var corePromise = null;
var lastModule = null; // kept so `read` can reach the files a run produced
var queue = Promise.resolve();

function describe(error) {
  if (!error) return 'unknown error';
  if (typeof error === 'string') return error;
  return String((error && error.message) || error);
}

function clean(text) {
  return String(text == null ? '' : text).replace(/\r?\n$/, '');
}

function loadCore() {
  if (corePromise) return corePromise;
  corePromise = new Promise(function (resolve, reject) {
    try {
      importScripts(CORE_SCRIPT);
    } catch (error) {
      reject(new Error('cannot load ' + CORE_SCRIPT + ': ' + describe(error)));
      return;
    }
    if (typeof createFFmpegCore !== 'function') {
      reject(
        new Error(
          'createFFmpegCore is missing; build the core with ' +
            'scripts/ffmpeg/build-web.sh (-sMODULARIZE=1 -sEXPORT_NAME=createFFmpegCore)'
        )
      );
      return;
    }
    resolve(createFFmpegCore);
  });
  return corePromise;
}

function instantiate(onStdout, onStderr) {
  return loadCore().then(function (factory) {
    return factory({
      // ffmpeg.wasm sits next to this worker; resolve it against the worker URL
      // so the app also works when served from a sub-path.
      locateFile: function (path) {
        return new URL(path, self.location.href).href;
      },
      print: function (line) {
        onStdout(clean(line));
      },
      printErr: function (line) {
        onStderr(clean(line));
      },
      noExitRuntime: true,
    });
  });
}

function callMain(module, args) {
  try {
    var status = module.callMain(args);
    return typeof status === 'number' ? status : 0;
  } catch (error) {
    // Emscripten signals exit() by throwing ExitStatus.
    if (error && typeof error.status === 'number') return error.status;
    throw error;
  }
}

function runInit(id) {
  var stdout = [];
  var stderr = [];
  return instantiate(
    function (line) {
      stdout.push(line);
    },
    function (line) {
      stderr.push(line);
    }
  )
    .then(function (module) {
      var exitCode = callMain(module, ['-version']);
      var version = stdout.find(function (line) {
        return line.indexOf('ffmpeg version') === 0;
      });
      postMessage({
        id: id,
        type: 'init',
        ok: exitCode === 0 && !!version,
        version: version || '',
        error: exitCode === 0 ? (version ? '' : 'unexpected -version output') : stderr.join('\n'),
      });
    })
    .catch(function (error) {
      postMessage({ id: id, type: 'init', ok: false, version: '', error: describe(error) });
    });
}

function runJob(id, args) {
  var stdout = [];
  var stderr = [];
  return instantiate(
    function (line) {
      stdout.push(line);
      postMessage({ id: id, type: 'line', stream: 'stdout', line: line });
    },
    function (line) {
      stderr.push(line);
      postMessage({ id: id, type: 'line', stream: 'stderr', line: line });
    }
  )
    .then(function (module) {
      lastModule = module;
      var exitCode = callMain(module, args);
      postMessage({
        id: id,
        type: 'done',
        exitCode: exitCode,
        stdout: stdout.join('\n'),
        stderr: stderr.join('\n'),
      });
    })
    .catch(function (error) {
      postMessage({
        id: id,
        type: 'done',
        exitCode: -1,
        stdout: stdout.join('\n'),
        stderr: (stderr.join('\n') + '\n' + describe(error)).trim(),
      });
    });
}

function readFile(id, path) {
  try {
    if (!lastModule) throw new Error('no FFmpeg run has produced files yet');
    var bytes = lastModule.FS.readFile(String(path));
    var copy = bytes.slice(); // detach from the wasm heap before transferring
    postMessage({ id: id, type: 'file', name: String(path).split('/').pop(), bytes: copy.buffer }, [
      copy.buffer,
    ]);
  } catch (error) {
    postMessage({ id: id, type: 'error', message: describe(error) });
  }
}

self.onmessage = function (event) {
  var message = event.data || {};
  // Serialise work: two FFmpeg instances at once would only fight over memory.
  queue = queue.then(function () {
    if (message.type === 'init') return runInit(message.id);
    if (message.type === 'run') return runJob(message.id, Array.from(message.args || [], String));
    if (message.type === 'read') return readFile(message.id, message.path);
    return Promise.resolve();
  });
};
}
