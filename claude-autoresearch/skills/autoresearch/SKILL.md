---
name: autoresearch-nono
description: Understands how to run autoresearch autonomous ML loops inside a nono sandbox with GPU access. Use when launching autoresearch, handling attestation, or diagnosing sandbox permission failures during ML training.
---

# autoresearch inside nono

You are running an autonomous ML research loop ([autoresearch](https://github.com/karpathy/autoresearch)) inside a **nono security sandbox**. nono enforces OS-level capability restrictions using Landlock (Linux). These restrictions cascade to all child processes, including GPU training subprocesses, and cannot be bypassed from within the session.

## Launching

Use `launch.sh` from the repo root. It verifies attestation before starting:

```bash
./launch.sh
```

Or manually:

```bash
~/.local/bin/nono run \
  --profile claude-code-autoresearch \
  --allow-gpu \
  --allow-cwd \
  --workdir ~/autoresearch-nono \
  -- "$(dirname "$(command -v node)")/node" \
     "$(dirname "$(command -v node)")/../lib/node_modules/@anthropic-ai/claude-code/cli.js" \
     --dangerously-skip-permissions
```

The node binary must be called directly (not via the `claude` shim) to avoid picking up the old system node inside the sandbox's clean PATH.

## Attestation

Before the first run, sign the program file for your corpus:

```bash
cd workload
nono trust sign ibd/program_ibd.md --keyref "file://$HOME/.config/nono/trust-key.pem"
nono trust verify ibd/program_ibd.md
```

`launch.sh` verifies this signature at startup. If verification fails, the session will not start.

## GPU access

GPU access requires two things:
1. `--allow-gpu` CLI flag when launching nono
2. `"allow_gpu": true` at the top level of the active profile (not inside the `security` section)

The `claude-code-autoresearch` profile (installed by this pack) already includes `allow_gpu: true`.

## When an operation is denied

If a file read, write, or bash command fails with EPERM, EACCES, or "Operation not permitted":

1. **Do NOT retry** the same operation.
2. Run `nono why` to diagnose:
   ```bash
   nono why --path /path/that/failed --op read 2>/dev/null
   ```
3. Present the user with options:
   - **Quick fix**: restart with `--allow /path/to/needed` added to the nono command
   - **Profile edit**: add the path to `~/.config/nono/profiles/claude-code-autoresearch.json` under `filesystem.allow`

## Common ML training permission issues

- **CUDA libs** (`/usr/local/cuda/`): already in the profile as read-only
- **`/proc/driver/nvidia`**: not in the allow list by default; add with `--allow /proc/driver/nvidia`
- **`/dev/shm`**: already allowed
- **HuggingFace cache** (`~/.cache/huggingface`): already allowed
- **uv package cache** (`~/.cache/uv`, `~/.local/share/uv`): already allowed

## Checking what is allowed

```bash
cat "$NONO_CAP_FILE" | jq .
```

Shows all allowed filesystem paths and whether network access is blocked.

## Audit log

Every session is recorded. Query after a run:

```bash
nono audit list --recent 5
nono audit show <session-id> --json
nono audit show <session-id> --json | jq '.denials'
```

## Experiment workflow

The agent operates autonomously:
1. Read `program_*.md` for the active corpus
2. Edit `workload/train.py` to try a change
3. Commit, run training, check `val_bpb` in `run.log`
4. Keep (leave committed) or discard (git reset) based on results
5. Record in `results.tsv` and loop

Never pause to ask the user during a run. If blocked by a sandbox denial, diagnose and present options — do not retry silently.
