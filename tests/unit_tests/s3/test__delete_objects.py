"""Test cases for `s3.delete_objects`."""

from files_api.s3.delete_objects import delete_s3_object
from files_api.s3.read_objects import object_exists_in_s3
from files_api.s3.write_objects import upload_s3_object
from tests.consts import TEST_BUCKET_NAME


def test_delete_existing_s3_object(mocked_aws: None): ...


def test_delete_nonexistent_s3_object(mocked_aws: None): ...
