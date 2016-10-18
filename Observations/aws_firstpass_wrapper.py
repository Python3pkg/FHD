#!/usr/bin/python

import pidly
import sys
import os

# Call this script on the command line:
# nohup python -u aws_firstpass_wrapper.py <obsfile_name> <version> > <log_filename> &

def main():

	#Parse command line arguments
	args = sys.argv
	obsfile_name = args[1]
	version = args[2]
	
	cotter_version = 5
	cotter_subversion = 1

	#Get obsids
	obsfile = open(obsfile_name, "r")
	obsids = [line.split( ) for line in obsfile.readlines()]
	obsids = [obs[0] for obs in obsids]
	obsfile.close()
	nonredundant_obsids = list(set(obsids))
	if len(obsids) != len(nonredundant_obsids):
		print "WARNING: Obs list contains redundant entries."
		obsids = nonredundant_obsids
		
	#Retrieve uvfits and metafits files from S3
	directory_contents = os.listdir('/tmp/uvfits')
	for obs_id in obsids:
		download_uvfits = True
		download_metafits = True
		for filename in directory_contents:
			if filename == '{}.uvfits'.format(obs_id):
				download_uvfits = False
			if filename == '{}.metafits'.format(obs_id):
				download_metafits = False
		if download_uvfits:
			print 'Downloading {}.uvfits from S3...'.format(obs_id)
			os.system('aws s3 cp s3://mwatest/uvfits/{}.{}/{}.uvfits /tmp/uvfits/{}.uvfits'.format(cotter_version, cotter_subversion, obs_id, obs_id))
		if download_metafits:
			print 'Downloading {}.metafits from S3...'.format(obs_id)
			os.system('aws s3 cp s3://mwatest/metafits/{}.{}/{}.metafits /tmp/uvfits/{}.metafits'.format(cotter_version, cotter_subversion, obs_id, obs_id))		
	
	#Run firstpass
	vis_file_list = ['/tmp/uvfits/{}.uvfits'.format(obs_id) for obs_id in obsids]
	output_directory = '/tmp'
	idl = pidly.IDL('/usr/local/bin/idl -IDL_DEVICE ps')
	for i, obs_id in enumerate(obsids):
		print 'Running firstpass on obsid {}...'.format(obs_id)
		idl('eor_firstpass_versions, /aws, obs_id = {}, output_directory = {}, version = {}, vis_file_list = {}'.format(obs_id, output_directory, version, vis_file_list[i]))
	idl.close()
	
	#Copy firstpass run to S3
	print 'Copying data from run {} to S3...'
	os.system('aws s3 cp /tmp/{} s3://mwatest/FHD_FIRST_PASS/{} --recursive'.format(version, version))
	
	#Delete uvfits and metafits files
	print 'Deleting local uvfits and metafits files...'
	os.system('rm -r /tmp/uvfits')
	

if __name__ == '__main__':
	main()