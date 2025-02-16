aws_region     = "us-east-1"
requester_name = "Michael Gatewood"

vpc_name            = "mlops"
vpc_cidr            = "172.31.0.0/16"
cluster_name        = "mlops"
task_cpu            = 2048
task_memory         = 4096
container_cpu       = 512
container_memory    = 1024
service_prefix      = "mlops"
service_name        = "mlops"
service_port        = 8501
healthcheck_path    = "/healthz"
ecr_repository_name = "mlops"