data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "conexoesmec" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true

  tags = {
    Name = "conexoesmec-application-vpc"
  }
}

resource "aws_internet_gateway" "conexoes-mec_igw" {
  vpc_id = aws_vpc.conexoes-mec_vpc.id
  tags = {
    Name = "conexoes-mec_igw"
  }
}

resource "aws_subnet" "conexoes-mec_public_subnet" {
  count             = var.subnet_count.public
  vpc_id            = aws_vpc.conexoes-mec_vpc.id

  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "conexoes-mec_public_subnet_${count.index}"
  }
}


resource "aws_subnet" "conexoes-mec_private_subnet" {
  count             = var.subnet_count.private
  vpc_id            = aws_vpc.conexoes-mec_vpc.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "conexoes-mec_private_subnet_${count.index}"
  }
}

resource "aws_route_table" "conexoes-mec_public_rt" { 
  vpc_id = aws_vpc.conexoes-mec_vpc.id
 
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.conexoes-mec_igw.id
  }
}

resource "aws_route_table_association" "public" {

  count          = var.subnet_count.public
  route_table_id = aws_route_table.conexoes-mec_public_rt.id
  subnet_id      = 	aws_subnet.conexoes-mec_public_subnet[count.index].id
}

resource "aws_route_table" "conexoes-mec_private_rt" { 
  vpc_id = aws_vpc.conexoes-mec_vpc.id 
}

resource "aws_route_table_association" "private" {
  count          = var.subnet_count.private
  route_table_id = aws_route_table.conexoes-mec_private_rt.id
  subnet_id      = aws_subnet.conexoes-mec_private_subnet[count.index].id
}

resource "aws_security_group" "conexoes-mec_web_sg" { 
  name        = "conexoes-mec_web_sg"
  description = "Security group for conexoes-mec web servers"
  
  vpc_id      = aws_vpc.conexoes-mec_vpc.id 
  ingress {
    description = "Allow all traffic through HTTP"
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH from my computer"
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    
    cidr_blocks = ["${var.my_ip}/32"]
  }
  
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "conexoes-mec_web_sg"
  }
}

resource "aws_security_group" "conexoes-mec_db_sg" {
  
  name        = "conexoes-mec_db_sg"
  description = "Security group for conexoes-mec databases"
  
  vpc_id      = aws_vpc.conexoes-mec_vpc.id

  ingress {
    description     = "Allow MySQL traffic from only the web sg"
    from_port       = "3306"
    to_port         = "3306"
    protocol        = "tcp"
    security_groups = [aws_security_group.conexoes-mec_web_sg.id]
  }
  
  tags = {
    Name = "conexoes-mec_db_sg"
  }
}

resource "aws_db_subnet_group" "conexoes-mec_db_subnet_group" {
  
  name        = "conexoes-mec_db_subnet_group"
  description = "DB subnet group for conexoes-mec"
  subnet_ids  = [for subnet in aws_subnet.conexoes-mec_private_subnet : subnet.id]
}


resource "aws_db_instance" "conexoes-mec_database" {
  
  allocated_storage      = var.settings.database.allocated_storage
  engine                 = var.settings.database.engine
  engine_version         = var.settings.database.engine_version
  instance_class         = var.settings.database.instance_class

  db_name                = var.settings.database.db_name
  username               = var.db_username
  password               = var.db_password
  
  db_subnet_group_name   = aws_db_subnet_group.conexoes-mec_db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.conexoes-mec_db_sg.id]
  skip_final_snapshot    = var.settings.database.skip_final_snapshot
}

resource "aws_key_pair" "conexoes-mec_kp" {
  key_name   = "conexoes-mec_kp"
  public_key = file("conexoes-mec_kp.pub")
}

resource "aws_instance" "conexoes-mec_web" {
  
  
  count                  = var.settings.web_app.count
  ami                    = data.aws_ami.ubuntu.id 
  instance_type          = var.settings.web_app.instance_type
  subnet_id              = aws_subnet.conexoes-mec_public_subnet[count.index].id 
  key_name               = aws_key_pair.conexoes-mec_kp.key_name
  vpc_security_group_ids = [aws_security_group.conexoes-mec_web_sg.id]
  
  tags = {
    Name = "conexoes-mec_web_${count.index}"
  }
}

resource "aws_eip" "conexoes-mec_web_eip" {
  count    = var.settings.web_app.count
  instance = aws_instance.conexoes-mec_web[count.index].id
  vpc      = true
	
  tags = {
    Name = "conexoes-mec_web_eip_${count.index}"
  }
}
