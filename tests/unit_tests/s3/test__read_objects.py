"""Test cases for `s3.read_objects`."""

from files_api.s3.read_objects import (
    fetch_s3_objects_metadata,
    fetch_s3_objects_using_page_token,
    object_exists_in_s3,
)
from tests.consts import TEST_BUCKET_NAME


def test_object_exists_in_s3(mocked_aws: None): ...


def test_pagination(mocked_aws: None): ...


def test_mixed_page_sizes(mocked_aws: None): ...


def test_directory_queries(mocked_aws: None): ...
