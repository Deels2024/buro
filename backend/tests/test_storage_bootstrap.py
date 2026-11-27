from unittest.mock import patch

import pytest
from botocore.exceptions import ClientError, EndpointConnectionError
from botocore.stub import Stubber

from app.core.config import settings
from app.services import storage_bootstrap
from app.services.storage import storage

BUCKET = {"Bucket": settings.s3_bucket}


def test_creates_missing_bucket_and_removes_public_policy():
    with Stubber(storage.client) as s:
        s.add_client_error("head_bucket", service_error_code="404", http_status_code=404, expected_params=BUCKET)
        s.add_response("create_bucket", {}, BUCKET)
        s.add_response("delete_bucket_policy", {}, BUCKET)
        storage.ensure_private_bucket()
        s.assert_no_pending_responses()


def test_existing_bucket_remains_private_without_data_changes():
    with Stubber(storage.client) as s:
        s.add_response("head_bucket", {}, BUCKET)
        s.add_client_error("delete_bucket_policy", service_error_code="NoSuchBucketPolicy", http_status_code=404,
                           expected_params=BUCKET)
        storage.ensure_private_bucket()
        s.assert_no_pending_responses()


def test_auth_error_fails_immediately_instead_of_recreating_bucket():
    with Stubber(storage.client) as s, patch.object(storage_bootstrap, "sleep") as pause:
        s.add_client_error("head_bucket", service_error_code="AccessDenied", http_status_code=403,
                           expected_params=BUCKET)
        with pytest.raises(ClientError, match="AccessDenied"):
            storage_bootstrap.initialize()
        pause.assert_not_called()
        s.assert_no_pending_responses()


def test_startup_retries_only_temporary_outage():
    outage = EndpointConnectionError(endpoint_url="http://minio.invalid")
    with patch.object(storage, "ensure_private_bucket", side_effect=[outage, None]) as setup, \
         patch.object(storage_bootstrap, "sleep") as pause:
        storage_bootstrap.initialize()
        assert setup.call_count == 2
        pause.assert_called_once()
    with patch.object(storage, "ensure_private_bucket", side_effect=outage), \
         patch.object(storage_bootstrap, "sleep") as pause, pytest.raises(EndpointConnectionError):
        storage_bootstrap.initialize(timeout=0)
        pause.assert_not_called()
