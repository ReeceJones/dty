static import std.stdio;

import core.stdc.string;
import core.sys.posix.stdlib;
import core.sys.linux.unistd;
import core.sys.linux.termios;
import core.sys.posix.sys.ioctl;
import core.sys.posix.sys.select;
import core.sys.linux.fcntl;

extern(C) void cfmakeraw(termios *termios_p);

int main(string[] args)
{
	string process = "/bin/bash";
	int masterDescriptor = posix_openpt(O_RDWR);
	if (masterDescriptor < 0)
	{
		std.stdio.writeln("Error opening master");
		return 1;
	}
	int returnCode = grantpt(masterDescriptor);
	if (returnCode != 0)
	{
		std.stdio.writeln("Error granting master");
		return 1;
	}
	returnCode = unlockpt(masterDescriptor);
	if (returnCode != 0)
	{
		std.stdio.writeln("Error unlocking master descriptor");
		return 1;
	}
	int slaveDescriptor = open(ptsname(masterDescriptor), O_RDWR);
	// fork that shit
	if (fork()) // parent
	{
		// The parent interacts with the master file so it has no need for the slave
		close(slaveDescriptor);

		returnCode = tcgetattr(masterDescriptor, &slave_orig_term_settings);
		new_term_settings = slave_orig_term_settings;
		cfmakeraw(&new_term_settings);
		tcsetattr(masterDescriptor, TCSANOW, &new_term_settings);

		char* input = cast(char*)malloc(0xff);
		fd_set inData;
		while(true) // read input
		{
			FD_ZERO(&inData);
			FD_SET(0, &inData);
			FD_SET(masterDescriptor, &inData);

			returnCode = select(masterDescriptor + 1, &inData, null, null, null);
			switch (returnCode)
			{
				case -1: 
					std.stdio.writeln("Exit code: ", returnCode);	
					return 1;
				default:
					if (FD_ISSET(0, &inData))
					{
						returnCode = cast(int)read(0, cast(void*)input, cast(int)0xff);
						if (returnCode > 0)
						{
							write(masterDescriptor, input, returnCode);
						}
						else
						{
							return 1;
						}
					}

					if (FD_ISSET(masterDescriptor, &inData))
					{
						returnCode = cast(int)read(masterDescriptor, input, 0xff);
						if (returnCode > 0)
						{
							write(1, input, returnCode);
						}
						else
						{
							return 1;
						}
					}
			}
		}
	}
	else // child
	{
		termios slave_orig_term_settings; // Saved terminal settings
		termios new_term_settings; // Current terminal settings
		// we are the child and are interacting with the salve pty, so we don't need the master
		close(masterDescriptor);
		returnCode = tcgetattr(slaveDescriptor, &slave_orig_term_settings);
		new_term_settings = slave_orig_term_settings;
		cfmakeraw(&new_term_settings);
		tcsetattr(slaveDescriptor, TCSANOW, &new_term_settings);

		close(0);
		close(1);
		close(2);

		dup(slaveDescriptor);
		dup(slaveDescriptor);
		dup(slaveDescriptor);

		close(slaveDescriptor);

		setsid();

		ioctl(0, TIOCSCTTY, 1);

		returnCode = execvp(cast(const(char*))&(("/bin/bash")[0]), cast(const(char**))[]);
	}

	return 0;
}
