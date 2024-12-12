provider "aws" {
  region = "us-east-1"
  
}

# VPC
resource "aws_vpc" "rohits_app_vpc" {
  cidr_block = "10.0.0.0/16" 
  
}

# Subnets
resource "aws_subnet" "rohits_public_subnet_1" {
  vpc_id                  = aws_vpc.rohits_app_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  
}

resource "aws_subnet" "rohits_public_subnet_2" {
  vpc_id                  = aws_vpc.rohits_app_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  
}

resource "aws_subnet" "rohits_private_subnet" {
  vpc_id                  = aws_vpc.rohits_app_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
  
}

# Internet Gateway and Route Table
resource "aws_internet_gateway" "rohits_igw" {
  vpc_id = aws_vpc.rohits_app_vpc.id
}

resource "aws_route_table" "rohits_public_route_table" {
  vpc_id = aws_vpc.rohits_app_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rohits_igw.id
  }
}

resource "aws_route_table_association" "rohits_public_subnet_1" {
  subnet_id      = aws_subnet.rohits_public_subnet_1.id
  route_table_id = aws_route_table.rohits_public_route_table.id
}

resource "aws_route_table_association" "rohits_public_subnet_2" {
  subnet_id      = aws_subnet.rohits_public_subnet_2.id
  route_table_id = aws_route_table.rohits_public_route_table.id
}

# Security Groups
resource "aws_security_group" "rohits_public_sg" {
  vpc_id = aws_vpc.rohits_app_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
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

resource "aws_security_group" "rohits_private_sg" {
  vpc_id = aws_vpc.rohits_app_vpc.id
  ingress {
    
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.rohits_public_sg.id] 
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
}

# Autoscaling Group
resource "aws_launch_template" "rohits_app_launch_template" {
  name          = "rohits-app-launch-template" 
  instance_type = "t2.micro"
  image_id      = "ami-0e2c8caa4b6378d8c" 
  iam_instance_profile {
    name = aws_iam_instance_profile.rohits_app_role_profile_5.name 
  }
  vpc_security_group_ids = [aws_security_group.rohits_public_sg.id] 
}
 
resource "aws_autoscaling_group" "rohits_app_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.rohits_public_subnet_1.id, aws_subnet.rohits_public_subnet_2.id]
 
  launch_template {
    id      = aws_launch_template.rohits_app_launch_template.id
    version = "$Latest"
  }
}

# Single EC2 Instance
resource "aws_instance" "rohits_private_instance" {
  ami           = "ami-0e2c8caa4b6378d8c" 
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.rohits_private_subnet.id
  vpc_security_group_ids = [aws_security_group.rohits_private_sg.id] 
  
  
}

# Load Balancers
resource "aws_lb" "rohits_app_alb" {
  name            = "rohits-app-alb"
  internal        = false 
  load_balancer_type = "application"
  security_groups = [aws_security_group.rohits_public_sg.id]
  subnets         = [aws_subnet.rohits_public_subnet_1.id, aws_subnet.rohits_public_subnet_2.id]
}

resource "aws_lb" "rohits_app_nlb" {
  name            = "rohits-app-nlb"
  internal        = true
  load_balancer_type = "network"
  subnets         = [aws_subnet.rohits_private_subnet.id]
}


resource "aws_lb_target_group" "rohits_alb_target_group" {
  name        = "rohits-alb-tg"
  port        = 80 
  protocol    = "HTTP" 
  vpc_id      = aws_vpc.rohits_app_vpc.id
  target_type = "instance"

  health_check {
    path                = "/" 
    interval            = 30 
    timeout             = 5 
    healthy_threshold   = 2 
    unhealthy_threshold = 2 
  }
}


resource "aws_lb_listener" "rohits_alb_listener" {
  load_balancer_arn = aws_lb.rohits_app_alb.arn 
  port              = 80
  protocol          = "HTTP"

  default_action { 
    type             = "forward" 
    target_group_arn = aws_lb_target_group.rohits_alb_target_group.arn 
  }
}


resource "aws_autoscaling_attachment" "rohits_asg_alb_attachment" {
  autoscaling_group_name = aws_autoscaling_group.rohits_app_asg.name
  lb_target_group_arn = aws_lb_target_group.rohits_alb_target_group.arn
}


resource "aws_lb_target_group" "rohits_nlb_target_group" {
  name        = "rohits-nlb-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.rohits_app_vpc.id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener for NLB
resource "aws_lb_listener" "rohits_nlb_listener" {
  load_balancer_arn = aws_lb.rohits_app_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rohits_nlb_target_group.arn
  }
}


resource "aws_lb_target_group_attachment" "rohits_nlb_instance_attachment" {
  target_group_arn = aws_lb_target_group.rohits_nlb_target_group.arn
  target_id        = aws_instance.rohits_private_instance.id
  port             = 80
}


# S3 Bucket
resource "aws_s3_bucket" "rohits_app_bucket" {
  bucket = "my-rohits-app-bucket"
  
}


resource "aws_s3_bucket_ownership_controls" "rohits_app_bucket_ownership_controls" {
  bucket = aws_s3_bucket.rohits_app_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"  # Object ownership set to bucket owner preferred
    #object writer
  }
}


resource "aws_s3_bucket_acl" "rohits_app_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.rohits_app_bucket_ownership_controls]  

  bucket = aws_s3_bucket.rohits_app_bucket.id
  acl    = "private"  
}


resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.rohits_app_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# IAM Role
resource "aws_iam_role" "rohits_app_role" {
  name = "rohits_app-role"

  assume_role_policy = jsonencode({ #jsconencode -- convert hcl into json
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
        
      }
    ]
  })
}

resource "aws_iam_policy" "rohits_s3_access_policy" {
  name        = "rohits_s3-access-policy"
  description = "Policy to provide full access to S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:*"],
        Resource = [
           
          "${aws_s3_bucket.rohits_app_bucket.arn}", # root of bucket
          "${aws_s3_bucket.rohits_app_bucket.arn}/*" # object
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rohits_attach_s3_policy" {
    
  role       = aws_iam_role.rohits_app_role.name
  policy_arn = aws_iam_policy.rohits_s3_access_policy.arn
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "rohits_app_role_profile_5" {
  
  name = "rohits_app-role-profile_5"
  role = aws_iam_role.rohits_app_role.name
}