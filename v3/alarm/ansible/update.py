#!/usr/bin/env python3
"""
Wrapper around ansible-playbook to easily update machines using an already
packaged payload (ex: just downloaded from drive golden images).

Target audience: chameleon users that just want to do an update.
"""

import argparse
import pathlib
import subprocess
import sys
import tempfile

INVENTORY_HEADER = """chameleon_physical:
  vars:
    username: cros
    ansible_python_interpreter: '/usr/bin/python'
    ansible_user: '{{username}}'
"""
UPDATE_PLAYBOOK_PATH = (pathlib.Path(__file__)/"../99_chameleon_update.play.yml").resolve()

def main():
  parser = argparse.ArgumentParser(description=__doc__)
  g = parser.add_mutually_exclusive_group(required=True)
  g.add_argument("--payload", "-p", action="store", metavar="*.btrfs.zst")
  g.add_argument("--oobe_only", "-o", action="store_true", dest="oobe",
                 help="perform initial install only (expand sd card + ec flashing), do not update to a new payload")
  parser.add_argument("--ssh_identity", "-i", action="store", metavar="testing_rsa",
                      default="", # `ssh -i ""` will work just fine if there's other keys defined
                      help="ssh keys to use if it's not already set in ~/.ssh/config. If in doubt you probably want the chromeos testing keys: $chroot/src/third_party/chromiumos-overlay/chromeos-base/chromeos-ssh-testkeys/files/testing_rsa")
  parser.add_argument("hostnames", nargs="*",
                     help="list of chameleon hostnames that will be updated (ex: chromeos8-row16-rack10-host9003-chameleon)")
  args = parser.parse_args()

  inventory_path = None
  if args.hostnames:
    # we have to create our own inventory
    inventory = tempfile.NamedTemporaryFile(mode="w+", suffix=".inventory.yml")
    inventory.write(INVENTORY_HEADER)
    inventory.write(f"    ansible_ssh_private_key_file: {args.ssh_identity!r}\n")
    inventory.write("  hosts:\n")
    for hostname in args.hostnames:
      inventory.write(f"    {hostname}:\n      ansible_host: {hostname}\n")
    inventory.flush()
    inventory.seek(0)
    inventory_path = inventory.name
    print(f"{inventory_path}:\n{inventory.read()}")

  cmd = [
    "ansible-playbook",
    UPDATE_PLAYBOOK_PATH,
    "--verbose", # looks prettier if there's a little more output
  ]
  if inventory_path is not None:
    cmd += ["-i", inventory_path]

  if args.payload:
    cmd += ["-e", f"update_payload={args.payload}"]

  if args.oobe:
    tags = [
      "resize",   # resize rootfs to fill the sd card
      "boot_pkg", # install ec firmware
    ]
    cmd += ["--tags", ','.join(tags)]

  # A little bit of verbose logs for debugging purposes
  subprocess.check_call(["echo", "Will run:"] + cmd)

  # Run the actual command
  subprocess.check_call(cmd)

if __name__ == "__main__":
  main()
