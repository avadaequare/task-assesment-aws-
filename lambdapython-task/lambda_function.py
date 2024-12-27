import boto3
import os
import time

# AWS Clients
ec2 = boto3.client('ec2')
s3 = boto3.client('s3')
ssm = boto3.client('ssm')

def lambda_handler(event, context):
    action = event.get("action", "").lower()  # Define the action via event trigger

    if action == "start_ec2":
        return start_ec2_instances(event)
    elif action == "stop_ec2":
        return stop_ec2_instances(event)
    elif action == "upload_file":
        return upload_file_to_s3(event)
    elif action == "download_file":
        return download_file_from_s3(event)
    else:
        return {"message": "Invalid action. Use start_ec2, stop_ec2, upload_file, or download_file."}

# 1. Start EC2 Instances
def start_ec2_instances(event):
    instance_ids = event.get("instance_ids", [])
    if not instance_ids:
        return {"message": "Instance IDs not provided."}

    response = ec2.start_instances(InstanceIds=instance_ids)
    return {"message": f"Starting instances: {instance_ids}", "response": response}

# 2. Stop EC2 Instances
def stop_ec2_instances(event):
    instance_ids = event.get("instance_ids", [])
    if not instance_ids:
        return {"message": "Instance IDs not provided."}

    response = ec2.stop_instances(InstanceIds=instance_ids)
    return {"message": f"Stopping instances: {instance_ids}", "response": response}

# 3. Upload a File to S3
def upload_file_to_s3(event):
    instance_id = event.get("instance_id")
    local_file_path = event.get("local_file_path")
    s3_bucket = event.get("s3_bucket")
    s3_key = event.get("s3_key", os.path.basename(local_file_path))

    if not all([instance_id, local_file_path, s3_bucket]):
        return {"message": "Missing parameters for file upload."}

    try:
        # Access the working directory of the EC2 instance
        working_directory = get_current_working_directory(instance_id)
        if not working_directory:
            return {"message": "Could not get the working directory from the EC2 instance."}

        # Ensure the file exists in the working directory (or modify for another directory)
        local_file_path = os.path.join(working_directory, local_file_path)

        # Upload file to S3 using SSM
        command = f"aws s3 cp {local_file_path} s3://{s3_bucket}/{s3_key}"
        run_command_on_instance(instance_id, command)

        return {"message": f"File uploaded to S3 bucket {s3_bucket} with key {s3_key}"}

    except Exception as e:
        return {"error": str(e)}

# 4. Download a File from S3 to EC2 instance
def download_file_from_s3(event):
    instance_id = event.get("instance_id")
    s3_bucket = event.get("s3_bucket")
    s3_key = event.get("s3_key")
    remote_file_path = event.get("remote_file_path")

    if not all([instance_id, s3_bucket, s3_key, remote_file_path]):
        return {"message": "Missing parameters for file download."}

    try:
        # Download file from S3 to EC2 instance using SSM
        command = f"aws s3 cp s3://{s3_bucket}/{s3_key} {remote_file_path}"
        run_command_on_instance(instance_id, command)

        return {"message": f"File {s3_key} downloaded from S3 bucket {s3_bucket} to {remote_file_path}"}
    except Exception as e:
        return {"error": str(e)}

# Helper Function: Get Current Working Directory from EC2 instance
def get_current_working_directory(instance_id):
    try:
        # Run "pwd" command on the EC2 instance to get the current working directory
        command = "pwd"
        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": [command]}
        )

        command_id = response['Command']['CommandId']
        max_retries = 5
        retry_delay = 2  # seconds

        # Retry until the command completes
        for attempt in range(max_retries):
            time.sleep(retry_delay)
            invocation_response = ssm.get_command_invocation(
                CommandId=command_id,
                InstanceId=instance_id,
            )

            if invocation_response['Status'] == "Success":
                # Return the current working directory
                return invocation_response['StandardOutputContent'].strip()
            elif invocation_response['Status'] == "Failed":
                raise Exception(
                    f"Command failed: {invocation_response['StandardErrorContent']}"
                )

        # If all retries are exhausted, raise an exception
        raise Exception("Failed to retrieve working directory within retry limit.")

    except Exception as e:
        print(f"Error getting working directory: {str(e)}")
        return None

# Helper Function: Run a Command on EC2 Instance Using SSM
def run_command_on_instance(instance_id, command):
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": [command]}
    )

    command_id = response['Command']['CommandId']
    max_retries = 5
    retry_delay = 2  # seconds

    for attempt in range(max_retries):
        time.sleep(retry_delay)
        invocation_response = ssm.get_command_invocation(
            CommandId=command_id,
            InstanceId=instance_id,
        )

        if invocation_response['Status'] == "Success":
            return invocation_response['StandardOutputContent']
        elif invocation_response['Status'] == "Failed":
            raise Exception(f"Command failed: {invocation_response['StandardErrorContent']}")

    raise Exception("Command execution did not complete within retry limit.")
	
	

# events
	
{
  "action": "download_file",
  "instance_id": "i-04f7b21a324e16836",
  "s3_bucket": "assessmenttasks3bucket",
  "s3_key": "uploaded/sample.txt",
  "remote_file_path": "/home/ec2-user/sample_downloaded.txt"
}

{
  "action": "upload_file",
  "instance_id": "i-1234567890abcdef",
  "local_file_path": "/home/ec2-user/sample.txt",
  "s3_bucket": "assessmenttasks3bucket",
  "s3_key": "uploaded/sample.txt"
}

{
  "action": "start_ec2",
  "instance_id": "i-1234567890abcdef"
}

{
  "action": "stop_ec2",
  "instance_id": "i-1234567890abcdef"
}
