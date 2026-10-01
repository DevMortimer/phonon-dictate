"""One-shot Phonon-2 worker.

The app starts this process when recording starts, so the model loads while the
user speaks. The worker reads one WAV path from stdin, prints one JSON line to
stdout, and exits. The exit frees the model memory.

`--prepare` downloads and verifies the model, compiles the MLX shaders on a
second of silence, and exits. The app runs it once during setup.
"""
import json
import sys


def load_model():
    # Same path as `phonon transcribe` (fermion/transcribe.py run_early).
    from fermion.transcribe import _resolve
    from fermion._speech import backends, fetch

    repo, key, pin, local_dir = _resolve("phonon-2")
    kind = backends.resolve("phonon-dictate")
    backends.require_engine_for(kind, pin.get("backend", ""))
    model_dir = local_dir if local_dir is not None else fetch.ensure(repo, key, pin)
    return backends.load(kind, model_dir, profile=key, backend=pin["backend"], quiet=True)


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main():
    try:
        speech = load_model()
        if "--prepare" in sys.argv:
            import numpy as np
            speech.transcribe_array(np.zeros(16000, dtype=np.float32))
            emit({"ready": True})
            return 0
        path = sys.stdin.readline().strip()
        if not path:
            return 0  # the app cancelled the recording
        text, decode_s, duration_s = speech.transcribe_detailed(path).triple()
        emit({"text": text, "duration_seconds": duration_s, "decode_seconds": decode_s})
        return 0
    except SystemExit as e:  # fermion exits with a message for user errors
        emit({"error": str(e.code)})
        return 1
    except Exception as e:  # report every failure to the app as JSON
        emit({"error": f"{type(e).__name__}: {e}"})
        return 1


if __name__ == "__main__":
    sys.exit(main())
