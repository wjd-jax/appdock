"""Resolve only the isolated test hostname to this machine's loopback address."""
import os
import socket
import ssl

_HOST = os.environ.get('APPDOCK_TEST_RESOLVE_HOST')
if _HOST:
    _getaddrinfo = socket.getaddrinfo

    def _isolated_getaddrinfo(host, port, *args, **kwargs):
        if host == _HOST:
            host = '127.0.0.1'
        return _getaddrinfo(host, port, *args, **kwargs)

    socket.getaddrinfo = _isolated_getaddrinfo

    _ca_cert = os.environ.get('APPDOCK_TEST_CA_CERT')
    if _ca_cert:
        _create_default_context = ssl.create_default_context

        def _isolated_default_context(*args, **kwargs):
            kwargs.setdefault('cafile', _ca_cert)
            return _create_default_context(*args, **kwargs)

        ssl.create_default_context = _isolated_default_context
