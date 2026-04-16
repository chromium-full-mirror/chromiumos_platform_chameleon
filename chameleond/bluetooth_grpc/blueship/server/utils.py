# Copyright 2026 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Utility functions for blueship server."""

import functools
import inspect

import grpc


def check_server_ready(func):
    """Decorator to check if the server is ready before executing the method.

    This decorator supports both:
    1. Unary rpc methods (async functions returning a single response).
    2. Server streaming rpc methods (async generators yielding multiple responses).

    If the server is not ready, it aborts the gRPC call with
    FAILED_PRECONDITION status.

    Args:
        func: The function to decorate.

    Returns:
        The decorated function (either async_wrapper or async_gen_wrapper).
    """

    @functools.wraps(func)
    async def async_wrapper(self, *args, **kwargs):
        """Wrapper for Unary-response methods (using return await)."""
        # gRPC aio methods have signature (self, request, context)
        # context is usually the second positional argument.
        if len(args) >= 2:
            context = args[1]
        else:
            context = kwargs.get("context")

        if not self.ctx.is_server_ready:
            await context.abort(
                grpc.StatusCode.FAILED_PRECONDITION, "Server not ready"
            )
        return await func(self, *args, **kwargs)

    @functools.wraps(func)
    async def async_gen_wrapper(self, *args, **kwargs):
        """Wrapper for Streaming-response methods (using async for/yield).

        Asynchronous generators (methods that use 'yield') cannot be wrapped
        by a simple 'return await' wrapper. This wrapper iterates over the
        decorated generator and yields its items back to the gRPC stream.
        """
        if len(args) >= 2:
            context = args[1]
        else:
            context = kwargs.get("context")

        if not self.ctx.is_server_ready:
            await context.abort(
                grpc.StatusCode.FAILED_PRECONDITION, "Server not ready"
            )

        # If server is ready, continue to stream.
        async for item in func(self, *args, **kwargs):
            yield item

    # Use inspect to determine if the decorated function is an async generator
    # (Server Streaming) or a regular coroutine (Unary).
    if inspect.isasyncgenfunction(func):
        return async_gen_wrapper
    return async_wrapper
