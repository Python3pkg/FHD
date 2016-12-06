import boto3
import base64

#ec2 = boto3.resource('ec2')
ec2 = boto3.client('ec2')
mycode = """#!/bin/bash 
mkdir -p /home/ubuntu/testfolder"""

#mycode = """#!/bin/bash -l
#aws s3 cp s3://mwatest/MWA_FHD_RTP.tar /usr/local/MWA_FHD_RTP.tar
#cd /usr/local
#tar xpvf MWA_FHD_RTP.tar
#export PATH="/usr/local/anaconda2/bin:$PATH"
#/usr/local/MWA/RTP/bin/still.py --server --config_file /usr/local/MWA/RTP/etc/aws_firstpass.cfg &"""



rc = ec2.request_spot_instances(
     SpotPrice = "0.65",
     InstanceCount = 1,
     LaunchSpecification={
     'ImageId' : 'ami-479c1a50',
     'UserData' : base64.b64encode(mycode),
     'KeyName' : 'jonrkey',
     'InstanceType' : 'c4.4xlarge',
     'NetworkInterfaces' : [{ "DeviceIndex": 0, 'SubnetId': 'subnet-61c9c716', 'Groups' : ['sg-9d7fe4e5'], "AssociatePublicIpAddress": True }] 
    }
)

for instance in rc:
   print(instance)
   #instance.wait_until_running()
   #instance.load()
   #print(instance.public_ip_address)
  

#instance = rc[0]
#instance.wait_until_running()

#instance.load()
#print(instance.public_ip_address)
