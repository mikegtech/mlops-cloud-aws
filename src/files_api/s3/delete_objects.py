"""Functions for deleting objects from an S3 bucket--the "D" in CRUD."""

from typing import Optional

try:
    from mypy_boto3_s3 import S3Client
except ImportError:
    ...


def delete_s3_object(bucket_name: str, object_key: str, s3_client: Optional["S3Client"] = None) -> None:
    """
    Delete an object from the S3 bucket.

    :param bucket_name: Name of the S3 bucket.
    :param object_key: Key of the object to delete.
    :param s3_client: Optional S3 client to use. If not provided, a new client will be created.
    """
    return
