# EC2-tooling
A tool to copy ec2 instances

Programming language: Why shell scripts:
We can combine lengthy and repetitive sequences of commands into a single, simple command, and generate a sequence of operations on one set of data so that it can be used for any similar set of data. And it is a good program that provides an interface layer between the Linux kernel and the end user.

Program flow:
1.Traverse all arguments we passed to the command, then do the correspond operations;
2.Add usage function to provide instructions when we get -h argument;
3.For the -n argument, we get the original instance's information, which include AVAILABILITY_ZONE, INSTANCE_TYPE, IMAGE_ID, CREDENTIAL, SECURITY_GROUP. Then create ten instance based on those information. Note that we need to use ssh-keyscan to check if the new instance's initialization state is ready, if not, we sleep 3 seconds until it finishes. If the process success, we write the corresponding instance insormation to a tast file.
4.For the -d argument, we get the host name for origin instance and their user name. Then use ssh-keygen to generate a public key for the original instance, then add it to the copied instance's .ssh/authorized_keys. After those operation we can use rsync to back up the corresponding directory because rsync only allow host to remote transfer operation.
5.For the -v argument, we set variable to true and print the detail information.
6.In the main function, we check if the host, user, directory exist, then we do the copy and sync operations.

Some corner cases:
aws-cli not installed or configured
task not finished(argument greater than 0)
copy number/instance-id/hostname/user/directory invalid
copy number too large
data in path is large (>GB)?
path encode problem ? [ignored]
path with ' ' (spaces)
relative path? convert to canonical path
initializing state consideration
permission denied(need root?)

Difficulties:
1.Checking initializing state. Using ssh-keyscan to see if the host in the known host list.
2.Using rsync replace scp. The scp allow user transfer data between remote host to remote host, But rsync can not. So what we do is to generate a public key in the original host and add the key to the .ssh/authorized_keys in the copied instances, and do the rsync at the original instance after that.

Git log:
refined task_create() routine, bug fix
soxhc committed 36 minutes ago
89175ce  
 @soxhc
refined main routine, add lock to task file read/write
soxhc committed 3 hours ago
87ba4e7  
Commits on Apr 15, 2017
 @soxhc
refactored task code, fixed a few bugs
soxhc committed 23 hours ago
d5ef3a3  
Commits on Apr 13, 2017
 @zh355245849
replace scp with rsync
zh355245849 committed 3 days ago
cf8517c  
 @soxhc
refactored main routines and error handling. refined output.
soxhc committed 3 days ago
4960795  
 @zh355245849
Update README.md
zh355245849 committed on GitHub 3 days ago
c10bb74  
 @zh355245849
Update verbose argument function
zh355245849 committed 3 days ago
039e02f  
Commits on Apr 12, 2017
 @soxhc
bug fix: create & sync should stop if error
soxhc committed 4 days ago
2ffa37d  
 @soxhc
Merge branch 'master' of github.com:zh355245849/EC2-tooling
soxhc committed 4 days ago
06876c5  
 @zh355245849
HW6_instruction
zh355245849 committed on GitHub 4 days ago
3f14a70  
 @soxhc
1. refactor code, integrated instance creation and synchronization. 2… …
soxhc committed 4 days ago
a539868  
Commits on Apr 11, 2017
 @zh355245849
change back variable _remote back
zh355245849 committed 6 days ago
a1456c1  
 @zh355245849
merge copy instances to main
zh355245849 committed 6 days ago
fc20014  
Commits on Apr 10, 2017
 @soxhc
merge code
soxhc committed 6 days ago
33683dc  
 @zh355245849
service call reduce to 1 time
zh355245849 committed 6 days ago
0772bf6  
 @soxhc
fix parameter passing bug
soxhc committed 6 days ago
b909676  
 @soxhc
Merge branch 'init'
soxhc committed 6 days ago
e317007  
 @soxhc
1. option parsing & verification 2. basic framework
soxhc committed 6 days ago
f5dbbb4  
 @zh355245849
Add copy ec2 instance function
zh355245849 committed 6 days ago
2558e53  
Commits on Apr 9, 2017
 @soxhc
modified option handler
soxhc committed 7 days ago
6c40f9c  
 @soxhc
design doc draft
soxhc committed 7 days ago
62bece9  

Initial outline
zh355245849 committed 7 days ago
74c27dc  
Commits on Apr 4, 2017
 @zh355245849
Create README.md
zh355245849 committed on GitHub 12 days ago
689f8c1  






