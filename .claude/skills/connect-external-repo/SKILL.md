---
name: connect-external-repo
description: Connect an existing local project folder to an external Git repository (GitHub, GitLab, Azure DevOps, Bitbucket) over SSH, in place, without re-cloning, so ignored local files (.env, certificates, keystores, local.properties, virtualenvs) and uncommitted work are never lost. Use this whenever the user wants to start pushing or pulling a project to a new or different remote, has accepted or received a collaborator invitation, wants to move a project from one host to another (for example Azure DevOps to GitHub), asks to "connect", "link", "hook up" or "point" a folder at a repo, or says "clone it the way I did before" while the project already exists locally. Also use it when they worry that .gitignore or secret files might be lost.
---

# Connect a local folder to an external repo

The usual instinct is `git clone` into a new folder. That's fine for a project you don't have yet, but when the project already exists locally, a fresh clone silently leaves behind everything Git doesn't track: `.env` files, payment certificates, `local.properties`, keystores, virtualenvs, and any uncommitted work. Those are often the hardest things to recreate. So the default here is to **connect the existing folder in place** and only clone when there is no local copy at all.

Work in this order: look → decide → change → verify → report. Steps 1–3 only read; nothing changes until step 4.

On Windows, run these in Git Bash (the user may run them in cmd, where `cd /d D:\path` is the equivalent of `cd`).

## 1. Check SSH access

```bash
ssh -T git@github.com        # or git@gitlab.com, git@ssh.dev.azure.com, ...
```

`Hi <username>! You've successfully authenticated` means it works, even though the exit code is 1 (GitHub offers no shell, so that's expected). Note the username: it's who the host will check permissions for. If it says `Permission denied (publickey)`, the user needs an SSH key added to their account before anything else.

## 2. Inspect the local folder

```bash
git status --short --branch
git branch -vv
git remote -v
git log --oneline -5
git config user.name; git config user.email
git ls-files | grep -i gitignore            # which .gitignore files are tracked
```

Then list what exists only on this machine, i.e. what a clone would lose:

```bash
git status --ignored --short | grep '^!!' \
  | grep -vE '(\.venv|node_modules|__pycache__|\.pytest_cache|\.ruff_cache|\.dart_tool|/build/)'
```

If the folder isn't a Git repo yet, there is no history to reconcile; see "Not a Git repo yet" below.

## 3. Inspect the remote and compare

```bash
git ls-remote git@github.com:<owner>/<repo>.git
```

- Empty output: the remote has no commits.
- `Repository not found`: wrong URL, or it's private and the user hasn't accepted the invitation yet.

If it has commits, add it under a temporary name so you can compare without touching the current setup:

```bash
git remote add incoming git@github.com:<owner>/<repo>.git   # skip if a remote with this URL already exists
git fetch incoming
git merge-base incoming/main HEAD || echo "unrelated histories"
git diff --stat incoming/main HEAD                           # empty = same files
git ls-tree -r --name-only incoming/main | grep -i gitignore # are the .gitignore files there?
```

## 4. Decide, then change

| What you found | What to do |
|---|---|
| Remote is empty | Make it `origin` and push the current branch. Confirm with the user first: it's the first push to a shared repo. |
| Same files as local (empty diff), whatever the history | Switch to a branch tracking the remote's `main`. The working tree doesn't change, and ignored and untracked files stay. |
| Remote is ahead and shares history | `git pull` (or rebase) as usual. |
| Different files **and** unrelated histories | Stop and ask. Options: start from the remote's `main` and carry local changes over on a branch, or merge with `--allow-unrelated-histories`. Never force-push over someone else's repo. |

To make the new remote `origin` (the layout a clone would give) while keeping the old one reachable, rename the old one **first**. The order matters, because the rename also moves the remote-tracking branches and updates branch upstreams:

```bash
git remote rename origin <old-host-name>     # e.g. azure; only if an old origin exists
git remote rename incoming origin            # or: git remote add origin <url>
git fetch origin
git switch -c main --track origin/main       # when files match or you're adopting the remote's main
```

Keep the old local branches rather than deleting them. They cost nothing and are the only copy of any commits that never reached a remote.

If the remote is missing `.gitignore` but local has one, commit and push it before anything else. Otherwise the next `git add .` could pick up secrets.

## 5. Verify

```bash
git remote -v
git branch -vv
git status --short --branch
ls -la <each local-only file from step 2>             # still there?
git check-ignore -v <.env> <certificate> <...>        # still ignored?
git push --dry-run origin main                        # write access, sends nothing
```

`ERROR: Permission to <owner>/<repo>.git denied to <username>` means read works but write doesn't. Usually the invitation hasn't been accepted: `https://github.com/<owner>/<repo>/invitations`.

## 6. Report to the user

Keep it short:

- What's connected (`origin` → URL), what the old remote was renamed to, and which branch they're on.
- Whether they can push yet, and the exact fix if not.
- Which local-only files were kept and confirmed still ignored. Suggest keeping a copy of `.env` and certificates in the team password manager, since Git will never hold them.
- The day-to-day commands: `git pull`, then a branch per change (`git switch -c area/short-description`), then `git push -u origin <branch>`.
- **Public repo:** if `ls-remote` worked before the invitation was accepted, the repo is public, so anything pushed is visible to everyone straight away.
- **Commit email:** if `user.email` is a work address and the repo is public, that address appears in public history. Mention `git config user.email <address>` before the first commit.

## Not a Git repo yet

When the folder has the project files but no `.git`:

```bash
git init
git remote add origin <url>
git fetch origin
git switch -c main --track origin/main
```

If a remote file has the same path as an untracked local file, `git switch` refuses rather than overwriting it. That's the safe outcome: show the user the list, compare the files, and let them choose which copy to keep.
