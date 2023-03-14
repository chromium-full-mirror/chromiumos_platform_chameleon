#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Build the Chameleon EC firmware.

This is the entry point for the custom firmware builder workflow recipe.
"""

import argparse
import multiprocessing
from pathlib import Path
import sys

from google.protobuf import json_format  # pylint: disable=import-error

from chromite.api.gen_sdk.chromite.api import firmware_pb2
from chromite.lib import cros_build_lib


HERE = Path(__file__).parent.resolve()
BUILD_DIR = Path("/tmp/chameleon_build")


def build(opts):
    """Builds the Chameleon board"""
    metric_list = firmware_pb2.FwBuildMetricList()

    cmd = [
        "zmake",
        f"-j{opts.cpus}",
        "--projects-dir",
        HERE,
        "-D",
        "build",
        "-a",
        "-B",
        BUILD_DIR,
    ]
    if opts.code_coverage:
        cmd.append("--coverage")
    cros_build_lib.run(cmd)
    opts.metrics.write_text(
        json_format.MessageToJson(metric_list), encoding="utf-8"
    )


def bundle(opts):
    """Bundle the artifacts for either firmware or code coverage."""
    if opts.code_coverage:
        bundle_coverage(opts)
    else:
        bundle_firmware(opts)


def write_metadata(opts, info):
    """Write the metadata about the bundle."""
    opts.metadata.write_text(json_format.MessageToJson(info), encoding="utf-8")


def bundle_coverage(opts):
    """Bundles the artifacts from code coverage into its own tarball."""
    info = firmware_pb2.FirmwareArtifactInfo()
    info.bcs_version_info.version_string = opts.bcs_version
    bundle_dir = opts.output_dir
    bundle_dir.mkdir(exist_ok=True)
    tarball_name = "coverage.tbz2"
    tarball_path = bundle_dir / tarball_name
    cmd = ["tar", "cvfj", tarball_path, "lcov.info"]
    cros_build_lib.run(cmd, cwd=BUILD_DIR)
    meta = info.objects.add()
    meta.file_name = tarball_name
    meta.lcov_info.type = (
        firmware_pb2.FirmwareArtifactInfo.LcovTarballInfo.LcovType.LCOV
    )
    (bundle_dir / "html").mkdir(exist_ok=True)
    cmd = ["mv", "lcov_rpt", bundle_dir / "html/"]
    cros_build_lib.run(cmd, cwd=BUILD_DIR)
    meta = info.objects.add()
    meta.file_name = "html"
    meta.coverage_html.SetInParent()

    write_metadata(opts, info)


def bundle_firmware(opts):
    """Bundles the artifacts from each target into its own tarball."""
    info = firmware_pb2.FirmwareArtifactInfo()
    info.bcs_version_info.version_string = opts.bcs_version
    bundle_dir = opts.output_dir
    bundle_dir.mkdir(exist_ok=True)
    build_dir = BUILD_DIR / "chameleon"
    artifacts_dir = build_dir / "output"
    tarball_name = "chameleon.firmware.tbz2"
    tarball_path = bundle_dir / tarball_name
    cmd = ["tar", "cvfj", tarball_path, "."]
    cros_build_lib.run(cmd, cwd=artifacts_dir)
    meta = info.objects.add()
    meta.file_name = tarball_name
    meta.tarball_info.type = (
        firmware_pb2.FirmwareArtifactInfo.TarballInfo.FirmwareType.EC
    )
    write_metadata(opts, info)


def test(opts):
    """Runs all of the unit tests for Chameleon firmware"""
    metrics = firmware_pb2.FwTestMetricList()

    # TODO: does chameleon have tests?  Do nothing now.
    opts.metrics.write_text(json_format.MessageToJson(metrics))


def main(args):
    """Builds and tests all of the Zephyr targets and reports build metrics"""
    opts = parse_args(args)

    if not hasattr(opts, "func"):
        print("Must select a valid sub command!")
        return -1

    # Run selected sub command function
    opts.func(opts)
    return 0


def parse_args(args):
    """Parse command line args."""
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument(
        "--cpus",
        default=multiprocessing.cpu_count(),
        help="The number of cores to use.",
    )

    parser.add_argument(
        "--metrics",
        dest="metrics",
        required=True,
        type=Path,
        help="File to write the json-encoded MetricsList proto message.",
    )

    parser.add_argument(
        "--metadata",
        required=False,
        type=Path,
        default=Path("/tmp/artifact_bundle_metadata"),
        help=(
            "Full pathname for the file in which to write build artifact "
            "metadata."
        ),
    )

    parser.add_argument(
        "--output-dir",
        required=False,
        type=Path,
        default=Path("/tmp/artifact_bundles"),
        help=(
            "Full pathname for the directory in which to bundle build "
            "artifacts."
        ),
    )

    parser.add_argument(
        "--code-coverage",
        required=False,
        action="store_true",
        help="Build host-based unit tests for code coverage.",
    )

    parser.add_argument(
        "--bcs-version",
        dest="bcs_version",
        default="",
        required=False,
        # TODO(b/180008931): make this required=True.
        help="BCS version to include in metadata.",
    )

    sub_cmds = parser.add_subparsers()
    build_cmd = sub_cmds.add_parser("build", help="Builds all firmware targets")
    build_cmd.set_defaults(func=build)

    bundle_cmd = sub_cmds.add_parser(
        "bundle",
        help="Creates a tarball containing build "
        "artifacts from all firmware targets",
    )
    bundle_cmd.set_defaults(func=bundle)

    test_cmd = sub_cmds.add_parser("test", help="Runs all firmware unit tests")
    test_cmd.set_defaults(func=test)

    return parser.parse_args(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
