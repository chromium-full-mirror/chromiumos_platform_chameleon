# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import logging
import os
import subprocess


class BtmonManager:
    """Manages a btmon process for capturing Bluetooth traffic.
    btmon is instructed to write to a fixed log file name (e.g., "btsnoop_log").

    Attributes:
        output_directory (str): Directory where btsnoop_log will be stored.
        log_filename (str): The fixed name for the log file (defaults to "btsnoop_log").
        btmon_process (subprocess.Popen, optional): The running btmon process.
        current_log_file_path (str): Absolute path to the btsnoop_log file.
    """

    def __init__(self, output_directory="btmon", log_filename="btsnoop_log"):
        """Initializes the BtmonManager.

        Args:
            output_directory (str): Directory where the log file will be created by btmon.
            log_filename (str): The fixed name of the log file btmon will write to.

        Raises:
            OSError: If the output directory cannot be created.
        """
        self.output_directory = os.path.abspath(output_directory)
        self.log_filename = log_filename
        self.btmon_process = None
        self.current_log_file_path = os.path.join(
            self.output_directory, self.log_filename
        )

        # Ensure the output directory exists
        if not os.path.exists(self.output_directory):
            try:
                os.makedirs(self.output_directory)
                logging.info(
                    f"BtmonManager: Created directory: {self.output_directory}"
                )
            except OSError as e:
                logging.error(
                    f"BtmonManager: Failed to create directory {self.output_directory}: {e}"
                )
                raise  # Directory creation is critical

    def start(self):
        """Starts the btmon process to capture Bluetooth traffic, writing to the fixed log file.

        Returns:
            (str or None): The absolute path to the log file if successful, None otherwise.
        """
        if self._is_running():
            self.stop()

        # The command tells btmon to write to the fixed self.current_log_file_path
        command = ["btmon", "-w", self.current_log_file_path]

        try:
            # stdout and stderr are discarded as -w handles the primary output.
            self.btmon_process = subprocess.Popen(
                command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            logging.info(
                f"BtmonManager: btsnoop log will be saved to: {self.current_log_file_path}"
            )
            return self.current_log_file_path
        except Exception as e:
            logging.error(
                f"BtmonManager: An error occurred while starting btmon: {e}"
            )
            self.btmon_process = None
            return None

    def stop(self, timeout=5):
        """Stops the running btmon process managed by this instance.

        Args:
            timeout (int): Time in seconds to wait for graceful termination.
        Returns:
            bool: True if successfully stopped or not running, False on error.
        """
        if self._is_running():
            logging.info(
                f"BtmonManager: Stopping btmon process (PID: {self.btmon_process.pid})..."
            )
            self.btmon_process.terminate()
            try:
                self.btmon_process.wait(timeout=timeout)
                logging.info("BtmonManager: btmon terminated gracefully.")
            except subprocess.TimeoutExpired:
                logging.warn(
                    f"BtmonManager: btmon did not terminate in {timeout}s, sending SIGKILL."
                )
                self.btmon_process.kill()
                self.btmon_process.wait()
                logging.info("BtmonManager: btmon killed.")
            except Exception as e:
                logging.error(
                    f"BtmonManager: Exception while stopping btmon: {e}"
                )
                self.btmon_process = None
                return False
            self.btmon_process = None
            return True
        elif self.btmon_process:
            logging.info("BtmonManager: btmon process was already terminated.")
            self.btmon_process = None
            return True
        else:
            logging.info(
                "BtmonManager: No btmon process was running or managed by this instance."
            )
            return True

    def _is_running(self):
        """Checks if the managed btmon process is currently running."""
        return (
            self.btmon_process is not None and self.btmon_process.poll() is None
        )
