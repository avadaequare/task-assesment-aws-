# VPC Resource
resource "aws_vpc" "Hello_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Hello_vpc"
  }
}

# Subnets
resource "aws_subnet" "subnets" {
  count                 = length(var.subnet_cidrs)
  vpc_id                = aws_vpc.Hello_vpc.id
  cidr_block            = var.subnet_cidrs[count.index]
  availability_zone     = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "Subneth${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "Hello_igw" {
  vpc_id = aws_vpc.Hello_vpc.id

  tags = {
    Name = "Hello-igw"
  }
}

# Route Table
resource "aws_route_table" "main_route_table" {
  vpc_id = aws_vpc.Hello_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.Hello_igw.id
  }

  tags = {
    Name = "HelloRouteTable"
  }
}

# Route Table Associations
resource "aws_route_table_association" "subnet_assoc" {
  count          = length(aws_subnet.subnets)
  subnet_id      = aws_subnet.subnets[count.index].id
  route_table_id = aws_route_table.main_route_table.id
}

# Security Group for Instances
resource "aws_security_group" "hello_sg" {
  vpc_id = aws_vpc.Hello_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WebSecurityGroup"
  }
}

# Instance Resource
resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = var.instance_type
  count         = 1
  key_name      = var.key_name
  subnet_id     = aws_subnet.subnets[0].id
  vpc_security_group_ids = [aws_security_group.hello_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd
              echo "<h1>Hello, World!</h1>" > /var/www/html/index.html
              sudo systemctl start httpd
              sudo systemctl enable httpd
              EOF

  tags = {
    Name = "HelloWorldApp-${count.index}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for Load Balancer
resource "aws_security_group" "lb_sg" {
  name_prefix = "lb-sg"
  vpc_id      = aws_vpc.Hello_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Load Balancer
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.subnets[*].id

  tags = {
    Name = "AppLoadBalancer"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.Hello_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_target_group_attachment" "app_instance_attachment" {
  count             = length(aws_instance.app) # Matches the count of EC2 instances
  target_group_arn  = aws_lb_target_group.app_tg.arn
  target_id         = aws_instance.app[count.index].id
  port              = 80
}


# Load Balancer Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Launch Template
resource "aws_launch_template" "app_lt" {
  name          = "app-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.lb_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y httpd
    echo "<h1>Hello, World!</h1>" > /var/www/html/index.html
    sudo systemctl start httpd
    sudo systemctl enable httpd
    EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "HelloWorldApp"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  min_size            = var.min_capacity
  max_size            = var.max_capacity
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = aws_subnet.subnets[*].id

  target_group_arns = [aws_lb_target_group.app_tg.arn]

  tag {
    key                 = "Name"
    value               = "HelloWorldApp"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
