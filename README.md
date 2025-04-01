# Ansible at SCI

Ansible is a very powerful tool for performing general tasks across fleets of computers. Or perhaps I should say "system", as Ansible is much larger and more complicated than most tools. In either case, it is complex and a lot of its power and utility is defined by how it is set up and configured. This document is aimed at describing how Ansible has been set up and used at SCI, as well as noting the principles that have informed and guided the decisions that led this this configuration. 

### Ansible is very powerful

Tools are neither good nor bad...that totally depends on how they are used. Which means that powerful tools can be wielded for powerful results, which may or may not be what was intended, desired, or expected. To protect against egregious shooting-one's-self-in-the-foot, Ansible has been set up in SCI not to be used directly, or at least not often  used directly. Instead, shell scripts have been written to call Ansible with at least some sanity and safety checks. That doesn't mean you can't run Ansible from the command line, but it has deliberately not been made super easy so that if you do want to run some ad-hoc script, you have to mean it.

This has led to a simple directory structure under `/sci-it/ansible`: 

  * **bin**: shell scripts that do things; these all support a `-s` argument that will show the Ansible command that would be envoked, so that you can easily see the inner workings of the command.
  * **etc**: configuration files, including `ansible.cfg` and any ansible-agent files
  * **playbooks**: where what Ansible knows how to do is kept  
  * **roles**: where common configurations are defined; the difference between playbooks in `playbooks` and things defined in `roles` is that `roles` is about how machines are configured and `playbooks` are specific things to do to them (such as updating)

A few scripts have been written in `/sci-it/sbin` that do not call Ansible directly but utilize the scripts in `/sci-it/ansible/bin`, notably the `update-hosts` and `reboot-hosts` scripts that are called weekly via cron. 

### Ansible has a very wide reach

Ansible really shines in large, modern environments where you have fleets of machines which can be categorized into types (e.g. web front end, application servers, etc) that all have nearly exact configurations. This is not the SCI environment and probably never will be.  As such, some of the killer features of Ansible, such as auto-discovery of inventory, roles, etc, have not been used here (maybe one day). Instead, the inventory is curated by hand in `etc/sci_inventory.yml`. The categories defined there are, for the most part, flexible and to be tailored to whatever the needs are for managing SCI resources. A couple of key points: 

  * most playbooks have Servers or AllHosts set as their default scope
  * AdminHosts are explicitly blacklisted from some playbooks, such as updates/reboots, given their importance to Ansible itself as well as general administration of hosts (as such, updates to those hosts need to be manually run as needed).

As an example of how to use the categories, here is how updates are currently set up in /etc/cron.d/update_hosts on babylon: 
```
  # Tuesday mornings, check to see if anything needs updating
  0 9 * * 2 root /sci-it/sbin/update-hosts -t -n 'Servers,!dublin' 
```
Note that this means that Ansible will update all hosts in the Servers group, except the host dublin. 

### Ansible is VERY configurable

Another way to say this is that there are a million ways to configure, set up, and run Ansible...possibly literally. Another benefit of hiding the Ansible bits and pieces behind shell scripts is that it allows for an evolution of the Ansible configuration without needing to evolve how people use it. 

For example, the playbooks directory is where the YAML files for each playbook is kept. There is a tasks subdirectory where some things have been broken out into individual YAML files for easier grokking of what is going on (or possible re-use in multiple playbooks). Currently, all handlers are kept in `handlers.yml`, which may, at some point, be best broken out similarly to tasks. Or roles might become a better way to structure all this...if all that administration tasks are handled through scripts, any changes will be transparent to Ansible users. 

## ansible-agent

Speaking of Ansible users, the scripts have been built to use the root account for talking to other machines when running commands. This leverages root's .ssh key which is managed by `/sci-it/ansible/bin/ansible-agent`. The code itself is pretty straight forward, so just read the code if you want to know how it works. 

NOTE: for any of the Ansible scripts to run, the ansible-agent process needs to be running on the main Ansible host (currently `babylon`). Which means, after any reboot, `sudo ansible-agent` should be run and the appropriate passphrase used to load root's ssh key. Yes, this means that anybody with open sudo access on the Ansible main host can do anything to any host in the inventory...caveat emptor. 

# Configuration vs Actions

Most commands in `/sci-it/ansible/bin` are things that you can do to a host- gather information about it, perform updates, reboot the system, etc. The main difference between configs and actions is idempotency, where a configuration will state what packages are installed, what services are running, etc, and an action makes a change that alters the host in a way that is more temporal/immediate. However, a lot of what we have set up in Ansible is about how machines are configured, which is maintained in the different roles that each machine is defined to have. These role are defined in the `roles` directory and the inventory files are similarly kept in th `inventory` directory. 

In the `inventory` directory there is a file called `AllHosts`; every host under Ansible control should appear in that file once, in either the Servers, InteractiveHosts, or Desktops section (depending on how the machine will be used). Other roles, e.g. mail servers, log servers, canaries, etc, all have their own files and any host can simply be added to those inventory files in order for those roles to apply to them. These roles/configs will be applied when `build-server` is run or when `apply-config` is run. 

# Examples

### Apply all configuration details

This is pretty straightforward: 
```
[@babylon]
~ > sudo apply_config -x folsom

PLAY [all] ********************************************************************************************************************************************************************

TASK [Gathering Facts] ********************************************************************************************************************************************************
ok: [folsom]

TASK [common : Remove buildtemp user] *****************************************************************************************************************************************
ok: [folsom]

TASK [common : Set timezone] **************************************************************************************************************************************************
ok: [folsom]

TASK [common : Configure /etc/hosts] *****************************
ok: [folsom]
.
.
.
```
This will make sure all the configuration details are set up correctly (eschew the `-x` flag to just check for any differences without apply any changes). If everything is set up correctly, there will be no changes to make and running this script is idempotent. 

### Update the host's operating system

To really evince how this set up works, let's work through an example: 
```
  [@babylon] /sci-it/ansible/bin:> which update-packages
  /sci-it/ansible/bin/update-packages
  [@babylon] /sci-it/ansible/bin:> update-packages -h
  
  update-packages: Ensure the packages installed on SCI hosts are up to date
  
  Usage:
    update-packages [ -h|--help ]
    update-packages [ -d|--diff ] [ -j|--json ] [ -s|--show ] [ -x|--execute ]
                <host|group>
  
  Arguments:
    -d|--diff        Show the details of the changes that will/would be done
    -h|--help        Show what you are seeing right now
    -j|--json        Output in JSON format
    -s|--show        Display the ansible command only
    -x|--execute     Actually execute the command (default is just check for changes)
    <host|group>     The target inventory group(s) or host(s)
  
  
  [@babylon] /sci-it/ansible/bin:>
```
The command `/sci-it/ansible/bin/update-packages` will do just that- update all the packages on the hosts. A few things to note: 
```
  [@babylon] ~:> update-packages
  ERROR: insufficient privileges (try sudo)
  [@babylon] ~:> sudo update-packages
  ERROR: Unspecified target groups/hosts
  [@babylon] ~:>
```
When run without privs, it will tell you so. When run without arguments, it will do nothing- this means you have to specifically say WHAT hosts you want to work on. 
```
  [@babylon] ~:> sudo update-packages -s Canaries
  /usr/bin/ansible-playbook -i /sci-it/ansible/etc/sci_inventory.yml --check --limit Canaries /sci-it/ansible/playbooks/update-packages.yml
  [@babylon] ~:>
```
The `-s` flag will show the Ansible command that will be run. Note that it specifies the inventory file explicitly (this does not work by default...again, to make it more likely for people to just use the shell scripts, and if they do want to run an ad-hoc command, they will have to explicity craft the command line by hand).  

Also note that the default is to include `--check`, which will not actually do anything besides just test to see what updates are needed. You need to explicitly add `--execute` to get the updates to actually run.  

The `--diff` option will show you all the packages that would be updated: 
```
  [@babylon] ~:> sudo update-packages -d 'AdminHosts,!langley,rio'
  Limiting scope to: AdminHosts,!langley,rio
  
  PLAY [AdminHosts,!langley,rio] *****************************************************************************************************
  
  TASK [Update and upgrade apt packages] ***********************************************************************************************
  Calculating upgrade...
  The following packages will be upgraded:
    apparmor bind9-dnsutils bind9-host bind9-libs libapparmor1 xkb-data
  6 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
  changed: [rio]
  Calculating upgrade...
  The following packages have been kept back:
    python3-update-manager update-manager-core
  The following packages will be upgraded:
    bind9-dnsutils bind9-host bind9-libs python3-zipp
  4 upgraded, 0 newly installed, 0 to remove and 2 not upgraded.
  changed: [babylon]
  
  PLAY RECAP ***************************************************************************************************************************
  babylon                    : ok=1    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
  rio                        : ok=1    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
  
  [@babylon] ~:>
```
At this time, the AdminHosts group contains two hosts- `babylon` and `langley`. By specifying `'AdminHosts,!langley,rio'` on the command line, it says to run Ansible against all of the hosts in AdminHosts, minus `langley`, and add in `rio`, which results in Ansible running against the two hosts `babylon` and `rio`. 

### Ad-hoc commands 

As mentioned above, to use Ansible at SCI, you need to have sudo access to run the commands kept in the `bin` directory; this relies on a key that is stored in the ssh-agent created by `ansible-agent` and stored in a file in the `etc` directcory. If you want to run something that isn't covered by one of the provided scripts, whether it is a playbook, task, or ad-hoc command line, the easiest way to do this is by leveraging the agent. 

`ansible-agent -i` makes this easy for you– this will output commands that will load up the agent when run in your shell . SOOO, if you want to run an ad-hoc Ansible command, you can just sudo to root and eval its output:
```
  [@babylon] ~:> sudo zsh
  [@babylon] ~:# eval `ansible-agent -i`
  [@babylon] ~:#  ansible Canaries -m ansible.builtin.shell -a 'uptime'
  oslo | CHANGED | rc=0 >>
   23:00:38 up 7 days, 19:47,  2 users,  load average: 0.46, 0.24, 0.20
  paris | CHANGED | rc=0 >>
   23:00:38 up 7 days, 19:47,  2 users,  load average: 0.38, 0.27, 0.26
  [@babylon] ~:#
```
This runs the command `uptime` on all the hosts defined in the Canaries section of the Ansible inventory (`/sci-it/ansible/etc/sci_inventory.yml`). 

# Updating via git

All this Ansible code lives on `babylon` and is run from there either through scripts, cron, etc. And obviously, duh, the code lives here in GitHub. This code is deployed to `babylon` by using a bare git repo and a `post-receive` hook. The bare repo lives in `/sci-it/ansible/.git` and all the `post-receive` hook does is deploy the `main` branch into `/sci-it/ansible` (note that the `post-receive` hook is kept in the `bin` directory and any updates to it will make it into `/sci-it/ansible/.git/hooks` when `main` is updated.    

To use this, all you need to do is check out the repo and add a second push desination to your copy (not, the first time you add a new destination it overwrites the existing one, so in order to get both you need to re-add the GitHub remote):  
```
[@sender]
../sci/repos > git clone git@github.com:SCIInstitute/SCIIT-Ansible
Cloning into 'SCIIT-Ansible'...
remote: Enumerating objects: 57, done.
remote: Counting objects: 100% (57/57), done.
remote: Compressing objects: 100% (46/46), done.
remote: Total 57 (delta 14), reused 54 (delta 11), pack-reused 0 (from 0)
Receiving objects: 100% (57/57), 34.61 KiB | 308.00 KiB/s, done.
Resolving deltas: 100% (14/14), done.

[@sender]
../sci/repos > cd SCIIT-Ansible

[@sender] (main)
../repos/SCIIT-Ansible > git remote -v
origin	git@github.com:SCIInstitute/SCIIT-Ansible (fetch)
origin	git@github.com:SCIInstitute/SCIIT-Ansible (push)

[@sender] (main)
../repos/SCIIT-Ansible > git remote set-url --add --push origin USERNAME@babylon.sci.utah.edu:/sci-it/ansible/.git

[@sender] (main)
../repos/SCIIT-Ansible > git remote -v
origin	git@github.com:SCIInstitute/SCIIT-Ansible (fetch)
origin	clake@babylon.sci.utah.edu:/sci-it/ansible/.git (push)

[@sender] (main)
../repos/SCIIT-Ansible > git remote set-url --add --push origin git@github.com:SCIInstitute/SCIIT-Ansible

[@sender] (main)
../repos/SCIIT-Ansible > git remote -v
origin	git@github.com:SCIInstitute/SCIIT-Ansible (fetch)
origin	clake@babylon.sci.utah.edu:/sci-it/ansible/.git (push)
origin	git@github.com:SCIInstitute/SCIIT-Ansible (push)

[@sender] (main)
../repos/SCIIT-Ansible >
```
Once this is done, when you push to the `main` branch on `origin`, it will both upload the code to GitHub and also then deploy to the repo on `babylon` that is used in production.


### Setup on babylon

In order to create/recreate the repository on `babylon` so that it may be used, follow the following steps: 
```
sudo mkdir -p /sci-it/ansible/.git
sudo chgrp -R sci-it /sci-it/ansible
sudo chmod -R 2775 /sci-it/ansible
cd /sci-it/ansible && git clone --bare git@github.com:SCIInstitute/SCIIT-Ansible .git
cd /sci-it/ansible/.git && git config --system --add safe.directory /sci-it/ansible/.git
```
Then copy post-recieve hook from the git repo and put it in .git/hooks/post-receive and make it executable.

