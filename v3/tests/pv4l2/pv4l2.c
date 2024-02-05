/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2024 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#define PY_SSIZE_T_CLEAN
#include<Python.h>
#include<linux/v4l2-subdev.h>
#include<sys/ioctl.h>
#include<sys/file.h>
#include<stdlib.h>
#include<string.h>
#include<stdio.h>
#include<errno.h>

/**
 * Get EDID from a video device
 * @param self
 * @param args [0] String with path to device
 * @return If there is no EDID set, the None is returned.
 *         Otherwise, the byte array with EDID is returned.
 */
static PyObject *pv4l2_GetEdid(PyObject *self, PyObject *args)
{
    const char *dev_name;
    int dev;
    struct v4l2_edid edid;
    PyObject* pEdid = NULL;
    int res;

    if(!PyArg_ParseTuple(args, "s", &dev_name)) {
        return NULL;
    }

    dev = open(dev_name, O_RDWR);
    if(dev < 0) {
        PyErr_SetFromErrno(PyExc_RuntimeError);
        return NULL;
    }

    memset(&edid, 0, sizeof(edid));
    res = ioctl(dev, VIDIOC_SUBDEV_G_EDID, &edid);
    if (res == 0 && edid.blocks > 0) {
        edid.edid = malloc(128 * edid.blocks);
        if (!edid.edid) {
            close(dev);
            return PyErr_NoMemory();
        }

        res = ioctl(dev, VIDIOC_SUBDEV_G_EDID, &edid);
    }

    if (res == 0) {
        pEdid = Py_BuildValue("y#", edid.edid, edid.blocks * 128);
    } else {
        pEdid = PyErr_SetFromErrno(PyExc_RuntimeError);
    }

    close(dev);
    if (edid.edid != NULL) {
        free(edid.edid);
    }

    return pEdid;
}

/**
 * Set EDID for a video device
 * @param self
 * @param args [0] String with path to device,
 *             [1] Empty byte array or bytes array with EDID to set
 * @return None in case of success
 */
static PyObject *pv4l2_SetEdid(PyObject *self, PyObject *args)
{
    const char *dev_name;
    int dev;
    struct v4l2_edid edid;
    int res;
    char* edidBuffer;
    Py_ssize_t edidBufferSize;
    PyObject *ret = Py_None;

    if (!PyArg_ParseTuple(args, "sy#", &dev_name, &edidBuffer, &edidBufferSize)) {
        if (!PyArg_ParseTuple(args, "s", &dev_name)) {
            return NULL;
        }

        PyErr_Clear();
        edidBuffer = NULL;
        edidBufferSize = 0;
    }

    if ((edidBufferSize % 128) != 0) {
        PyErr_BadArgument();
        return NULL;
    }

    dev = open(dev_name, O_RDWR);
    if (dev < 0) {
        return PyErr_SetFromErrno(PyExc_RuntimeError);
    }

    memset((char*)&edid, 0, sizeof(edid));
    edid.start_block = 0;
    edid.edid = (unsigned char*)edidBuffer;
    edid.blocks = edidBufferSize / 128;

    res = ioctl(dev, VIDIOC_SUBDEV_S_EDID, &edid);
    if (res != 0) {
        ret = PyErr_SetFromErrno(PyExc_RuntimeError);
    } else {
        ret = Py_None;
        Py_INCREF(Py_None);
    }

    close(dev);
    return ret;
}

/**
 * Clear EDID of a video device
 * @param self
 * @param args [0] String with path to device
 * @return None in case of success
 */
static PyObject *pv4l2_ClearEdid(PyObject *self, PyObject *args)
{
    return pv4l2_SetEdid(self, args);
}

static PyObject *pv4l2_GetFormats(PyObject *self, PyObject *args)
{
    const char *dev_name;
    struct v4l2_fmtdesc fmt_desc;
    int dev;

    if (!PyArg_ParseTuple(args, "s", &dev_name)) {
        return NULL;
    }

    dev = open(dev_name, O_RDWR);
    if (dev < 0) {
        PyErr_SetFromErrno(PyExc_RuntimeError);
        return NULL;
    }

    memset(&fmt_desc, 0, sizeof(fmt_desc));
    fmt_desc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;

    PyObject* formatsArray = PyList_New(0);
    while (!ioctl(dev, VIDIOC_ENUM_FMT, &fmt_desc)) {
        struct v4l2_frmsizeenum size;
        memset(&size, 0, sizeof(size));
        size.pixel_format = fmt_desc.pixelformat;

        while (!ioctl(dev, VIDIOC_ENUM_FRAMESIZES, &size)) {
            struct v4l2_frmivalenum fps;
            memset(&fps, 0, sizeof(fps));
            fps.pixel_format = size.pixel_format;
            fps.width = size.discrete.width;
            fps.height = size.discrete.height;

            PyObject *obj = PyDict_New();
            PyDict_SetItemString(obj, "width", PyLong_FromLong(fps.width));
            PyDict_SetItemString(obj, "height", PyLong_FromLong(fps.height));
            PyList_Append(formatsArray, obj);

            size.index++;
        }

        fmt_desc.index++;
    }

    close(dev);

    return formatsArray;
}

static PyMethodDef pv4l2Methods[] = {
    {"GetEdid", pv4l2_GetEdid, METH_VARARGS, NULL},
    {"SetEdid", pv4l2_SetEdid, METH_VARARGS, NULL},
    {"ClearEdid", pv4l2_ClearEdid, METH_VARARGS, NULL},
    {"GetFormats", pv4l2_GetFormats, METH_VARARGS, NULL},

    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef pv4l2Module = {
    PyModuleDef_HEAD_INIT, "pv4l2", NULL, -1, pv4l2Methods
};

PyMODINIT_FUNC PyInit_pv4l2(void)
{
    PyObject* module = PyModule_Create(&pv4l2Module);

    PyModule_AddStringConstant(module, "VIDEO_DEV_SST", "/dev/video5");

    PyObject *mstList = PyList_New(4);
    PyList_SetItem(mstList, 0, PyUnicode_FromString("/dev/video1"));
    PyList_SetItem(mstList, 1, PyUnicode_FromString("/dev/video2"));
    PyList_SetItem(mstList, 2, PyUnicode_FromString("/dev/video3"));
    PyList_SetItem(mstList, 3, PyUnicode_FromString("/dev/video4"));
    PyModule_AddObject(module, "VIDEO_DEV_MST", mstList);

    return module;
}
