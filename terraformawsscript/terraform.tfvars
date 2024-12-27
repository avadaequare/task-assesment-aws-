region = "us-east-1"
vpc_cidr = "10.0.0.0/16"
subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
availability_zones = ["us-east-1a", "us-east-1b"]
ami_id = "ami-0c02fb55956c7d316"
instance_type = "t2.micro"
key_name = "asses.key"
min_capacity = 1
max_capacity = 3
desired_capacity = 2
