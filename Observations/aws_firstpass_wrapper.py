#!/usr/bin/python

import pidly
import sys
import os

# Call this script on the command line:
# nohup python aws_firstpass_wrapper.py <obs_id> <version> <log_filename> > /tmp/<log_filename> &

def main():

	#Parse command line arguments
	args = sys.argv
	obs_id = args[1]
	version = args[2]
	log_filename = args[3]
	
	cotter_version = 5
	cotter_subversion = 1
		
	try:	
		#Retrieve uvfits and metafits files from S3
		if not os.path.isdir('/tmp/uvfits'):
			os.system('mkdir /tmp/uvfits')
		directory_contents = os.listdir('/tmp/uvfits')

		download_uvfits = True
		download_metafits = True
		for filename in directory_contents:
			if filename == '{}.uvfits'.format(obs_id):
				download_uvfits = False
			if filename == '{}.metafits'.format(obs_id):
				download_metafits = False
		if download_uvfits:
			print 'Downloading {}.uvfits from S3...'.format(obs_id)
			sys.stdout.flush()
			os.system('aws s3 cp s3://mwatest/uvfits/{}.{}/{}.uvfits /tmp/uvfits/{}.uvfits'.format(cotter_version, cotter_subversion, obs_id, obs_id))
		if download_metafits:
			print 'Downloading {}.metafits from S3...'.format(obs_id)
			sys.stdout.flush()
			os.system('aws s3 cp s3://mwatest/metafits/{}.{}/{}.metafits /tmp/uvfits/{}.metafits'.format(cotter_version, cotter_subversion, obs_id, obs_id))
	except:
		print 'ERROR downloading obsid {} from S3.'.format(obs_id)
		sys.stdout.flush()
		error_procedure(log_filename)
	
	try:
		#Run firstpass
		vis_file_list = '/tmp/uvfits/{}.uvfits'.format(obs_id)
		output_directory = '/tmp'
		if not os.path.isdir('/tmp/{}'.format(version)):
			os.system('mkdir /tmp/{}'.format(version))
		idl = pidly.IDL('/usr/local/bin/idl -IDL_DEVICE ps')
		print 'Running firstpass on obsid {}...'.format(obs_id)
		sys.stdout.flush()
		idl('eor_firstpass_versions, /aws, obs_id = \'{}\', output_directory = \'{}\', version = \'{}\', vis_file_list = \'{}\''.format(obs_id, output_directory, version, vis_file_list))
		idl.close()
	except:
		print 'ERROR running firstpass.'
		sys.stdout.flush()
		error_procedure(log_filename)
	
	#Copy firstpass run to S3
	print 'Copying data from run {} to S3...'.format(version)
	sys.stdout.flush()
	try:
		os.system('aws s3 cp /tmp/{} s3://mwatest/FHD_FIRST_PASS/{} --recursive'.format(version, version))
	except:
		print 'ERROR uploading data to S3.'
		sys.stdout.flush()
		error_procedure(log_filename)
		
	#Delete uvfits and metafits files
	print 'Deleting local uvfits and metafits files...'
	sys.stdout.flush()
	os.system('rm -r /tmp/uvfits')
	
	#Copy log file to S3
	os.system('aws s3 cp /tmp/{} s3://mwatest/FHD_FIRST_PASS/{}'.format(log_filename, log_filename))

	
def error_procedure(log_filename):

	os.system('aws s3 cp /tmp/{} s3://mwatest/FHD_FIRST_PASS/{}'.format(log_filename, log_filename))
	sys.exit(1)
	

if __name__ == '__main__':
	main()
