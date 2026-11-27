"""Prepare the private media bucket before the API starts."""

import logging
from time import monotonic, sleep

from botocore.exceptions import (
    ClientError,
    ConnectionClosedError,
    ConnectTimeoutError,
    EndpointConnectionError,
    ReadTimeoutError,
)

from app.services.storage import storage

log = logging.getLogger(__name__)
TRANSIENT_NETWORK_ERRORS = (
    ConnectionClosedError,
    ConnectTimeoutError,
    EndpointConnectionError,
    ReadTimeoutError,
)


def initialize(*, timeout: float = 120) -> None:
    deadline = monotonic() + timeout
    while True:
        try:
            storage.ensure_private_bucket()
            return
        except TRANSIENT_NETWORK_ERRORS:
            if monotonic() >= deadline:
                raise
        except ClientError as error:
            status = error.response.get("ResponseMetadata", {}).get("HTTPStatusCode", 0)
            if status not in {429, 500, 502, 503, 504} or monotonic() >= deadline:
                raise
        log.warning("Object storage is starting; retrying")
        sleep(2)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    initialize()
