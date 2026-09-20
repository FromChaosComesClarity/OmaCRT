# Machine setup for OmaCRT development

System-level prerequisites, outside the git repo (udev rules and group
membership are per-machine, not project files). Run once per machine.

## Gamepad daemon prerequisites

```bash
# Python bindings for the Linux input subsystem (reading the pad)
sudo pacman -S python-evdev

# Let a non-root process create a virtual input device (emitting synthetic
# key/mouse events) without running as root
echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' | sudo tee /etc/udev/rules.d/60-omacrt-uinput.rules
sudo udevadm control --reload-rules

# /dev/uinput already exists at boot, created before the new rule — a
# running kernel module reload is the reliable way to get udev to
# re-apply permissions to the existing node rather than a fresh one:
sudo modprobe -r uinput && sudo modprobe uinput
# (if that no-ops because uinput is built-in rather than a module on some
# kernel config, a reboot forces it instead)

sudo usermod -aG input "$USER"
```

**The group membership needs a fresh login (or reboot) to take effect** —
`id "$USER"` shows the new group immediately, but a shell/session that was
already open when `usermod` ran keeps its old group list (`groups` in that
session won't show `input`) until it's replaced. Confirmed by testing both
commands back to back on 2026-09-20 on the dev machine: `/dev/uinput` was
`crw-rw---- root input` right after the module reload, but a Claude Code
Bash session open since before the `usermod` call still reported only
`jose wheel` from `groups`, not `input`.

## Verify

```bash
python3 -c "import evdev"        # no output = ok
ls -l /dev/uinput                 # expect: crw-rw---- root input
groups                            # expect "input" listed (after a fresh login)
```
