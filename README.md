# EC2-tooling
A tool to copy ec2 instances

Programming language: Why shell scripts:
We can combine lengthy and repetitive sequences of commands into a single, simple command, and generate a sequence of operations on one set of data so that it can be used for any similar set of data. And it is a good program that provides an interface layer between the Linux kernel and the end user.

Program flow:
1.Traverse all arguments we passed to the command, then do the correspond operations;
2.Add usage function to provide instructions when we get -h argument;
3.For the -n argument, we get the original instance's information, which include AVAILABILITY_ZONE, INSTANCE_TYPE, IMAGE_ID, CREDENTIAL, SECURITY_GROUP. Then create ten instance based on those information. Note that we need to use ssh-keyscan to check if the new instance's initialization state is ready, if not, we sleep 3 seconds until it finishes. If the process success, we write the corresponding instance insormation to a tast file.
4.For the -d argument, we get the host name for origin instance and copied instances as well as their user name. Then use scp to copy the corresponding directory to the new instances.
5.For the -v argument, we set variable to true and print the detail information.
6.In the main function, we check if the host, user, directory exist, then we do the copy and sync operations.

Some corner cases:
aws-cli not installed or configured
task not finished(argument greater than 0)
copy number/instance-id/hostname/user/directory invalid
initializing state consideration
permission denied(need root?)

Difficulties:
1.Check initializing state. I don't know how ssh-keyscan works until my parter's hints.

Git log:
commit 039e02f28812deb8aefa10ff54660fbd1bce624f
Author: han <355245849@qq.com>
Date:   Thu Apr 13 15:24:37 2017 +0000

    Update verbose argument function

commit 2ffa37d7004c79a096dbe89e4ff2779c2e9b9018
Author: Yangmu Jiang <celsius.j@gmail.com>
Date:   Wed Apr 12 16:38:36 2017 -0400

    bug fix: create & sync should stop if error

commit 06876c5075b762b48ec56c2898057973800b9b83
Merge: a539868 3f14a70
Author: Yangmu Jiang <celsius.j@gmail.com>
Date:   Wed Apr 12 16:03:09 2017 -0400

    Merge branch 'master' of github.com:zh355245849/EC2-tooling

commit 3f14a70232f56de50b8201cc7e9c980fa65e4a7d
Author: han <355245849@qq.com>
Date:   Wed Apr 12 16:00:33 2017 -0400

    HW6_instruction

commit a53986809e9c3c75a640b8e5b90f30d250e144ce
Author: Yangmu Jiang <celsius.j@gmail.com>
Date:   Wed Apr 12 15:58:31 2017 -0400

    1. refactor code, integrated instance creation and synchronization.  2. add some mid-step verificati

commit a1456c13ba0e4e2611052e14513b8b45aa292453
Author: han <355245849@qq.com>
Date:   Tue Apr 11 05:05:04 2017 +0000

    change back variable _remote back

commit fc200143b73ad337d7c055b7d8af8b02769e3bc4
Author: han <355245849@qq.com>
Date:   Tue Apr 11 04:42:05 2017 +0000

    merge copy instances to main

commit 33683dc6bc77f73a4600044f8efda72f7a1f34c3
Merge: b909676 0772bf6
Author: Yangmu Jiang <celsius.j@gmail.com>
Date:   Mon Apr 10 20:31:07 2017 -0400

    merge code

commit 0772bf6312036bb8295a3b4817a03ee65d2a2522
Author: han <355245849@qq.com>
Date:   Tue Apr 11 00:18:58 2017 +0000

    service call reduce to 1 time

commit b9096767a62299c2dca18893e312d938f16031e8
Author: Yangmu Jiang <celsius.j@gmail.com>
Date:   Mon Apr 10 14:39:55 2017 -0400

    fix parameter passing bug

commit e317007b3f7955f9939805694807b968c59ec6b7
Merge: 2558e53 f5dbbb4
Author: Yangmu Jiang <celsius.j@gmail.com>
Date:   Mon Apr 10 14:34:25 2017 -0400

    Merge branch 'init'

commit f5dbbb44531f929261d773f9e2b95f1d11994943
Author: Yangmu Jiang <celsius.j@gmail.com>
Date:   Mon Apr 10 14:06:46 2017 -0400

    1. option parsing & verification 2. basic framework

commit 2558e53bed96e1cdd4d41762faec35d2ff0d8f2b
Author: han <355245849@qq.com>
Date:   Mon Apr 10 17:59:20 2017 +0000

    Add copy ec2 instance function

commit 6c40f9cecaa62becbeb7b733ead0b77d09d75431
Author: Yangmu Jiang <celsius.j@gmail.com>
Date:   Sun Apr 9 17:33:00 2017 -0400

    modified option handler

commit 62bece96977d5e810489f141d996caecb6a6e39b
Author: Yangmu Jiang <celsius.j@gmail.com>
Date:   Sun Apr 9 15:50:18 2017 -0400

    design doc draft

commit 74c27dc1eebcaf065cd6d89c1a4367c8ae32c7fe
Author: han <355245849@qq.com>
Date:   Sun Apr 9 18:52:34 2017 +0000

    Initial outline

commit 689f8c12ddd9ac5aca50ff4c8941a87c0246937f
Author: han <355245849@qq.com>
Date:   Tue Apr 4 20:37:31 2017 -0400

    Create README.md








