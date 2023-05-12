# Chameleon v3 Utilitary XMLRPC Clients

In this folder you can find a couple utilities that should help
exercise Chameleon v3 by making the appropriate XMLRPC calls.

`python3 -i interactive.py` should give an interactive prompt to exercise any
of the XMLRPC methods. Very useful when testing newly added server methods or
when you're trying to reproduce some chameleon behavior using first principles
(without a complex test fixture in the way).

`screenshot.py` exercises the whole frame capture flow, ouputting a standard
image file. If this works, your chameleon and the DUT is likely in good shape.

`stress_edid.py` runs continously runs through a loop of edids to make
sure the whole video path is working. We found quite a few chameleon bugs where
the EDID was getting intermittently stuck/corrupted in one place or another.
One can consider this a chameleon plug/unplug stress test.

## Implementing your own clients

You can use `interactive.py` to learn how to do it, but please don't just import it.
You really only need the following lines to make a python client that
acts almost the same as `interactive.py`:

```python
import xmlrpc.client
chameleon = xmlrpc.client.ServerProxy("http://localhost:9992")
chameleon.Plug(0)
```
