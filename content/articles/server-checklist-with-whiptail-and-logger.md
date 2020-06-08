---
title: "Server checklist with whiptail and logger."
author: "Ally"
summary: "An interactive CLI for logging server audits in `bash` with `whiptail `and `logger`."
publishDate: 2020-01-18T12:00:00+01:00
tags: ['bash', 'whiptail', 'logger']
draft: false
---

As part of my morning routine I carry out some checks for our systems.

These include things like:

* Checking that email templates have all the mandatory variable placeholders, e.g. we expect to replace `{{ surname }}` - so if this isn't in the template we need to fix it. This is checked daily by a cron, and a summary is emailed.
* Checking API requests and investigate if there are any taking longer than usual.
* Checking previous day app logs to see if anything needs action.
* Checking EC2 and RDS backups have been created.
* Checking `apt` and other various logs.
* Running software updates.

I setup a bunch of [`whiptail`](https://en.wikibooks.org/wiki/Bash_Shell_Scripting/Whiptail) questions and log the answers to `syslog` with [`logger`](https://linux.die.net/man/1/logger). Our `syslog` messages go to papertrail, so we can have a history of these checks. This is also handy for other developers to easily see any notes.

![server-checks](/img/articles/server-checks/server-checks.png)

---

The code! I start with logging which server the check is being run on.

```bash
logger --tag 'servercheck' "Starting: $(hostname)"
```

Then for each check, I ask if we want to perform it. To ask the question:

```bash
whiptail --title "Perform Check" \
  --yesno "Do you want to run developer_alerts check?\n\
  This is for email templates and API requests, etc." \
  8 78 && developer_alerts
```

I do this because some checks are to do with emails and AWS things, so once these have been done once (I start on production server)
we don't need to do these checks on the next server.

![Server Check Question](/img/articles/server-checks/screens/01.png)

If you answer yes, then it will run whatever is in the function `developer_alerts`.

```bash
function email_more_info
{
  logger --tag 'servercheck/developer_alerts' "Email Templates: Has errors"

  INFO=$(whiptail \
    --inputbox "What was the error raised?" 8 78 \
    --title "More Information" \
    3>&1 1>&2 2>&3
  )
  ES=$?
  
  if [ $ES = 0 ]; then
    logger --tag 'servercheck/developer_alerts' "Email Templates: Info: $INFO"
  else
    logger --tag 'servercheck/developer_alerts' "Email Templates: Info: none given"
  fi
}

function developer_alerts
{
  whiptail --title "Email" \
    --yesno "Did the developer alert for email template health check show any errors?" 8 78 \
    && email_more_info \
    || logger --tag 'servercheck/developer_alerts' "Email Templates: Has no issues"

  # similar check for API is ommited

  logger --tag 'servercheck/developer_alerts' "Done!"
}
```

In `email_more_info` when asking for input we need to get the exit code from `whiptail` to see whether we selected `Ok` or `Cancel`.
If `Ok`, the input goes to `stderr` so need to swap `stderr` to `stdout` to set `INFO` to be what the user input.

![Server Check Question](/img/articles/server-checks/screens/04.png)

The next check which is a bit different is AWS checks, first it prompts you with some instructions.

![Server Check Info](/img/articles/server-checks/screens/02.png)

Then there is a list of volumes we expect to be backed up.

![Server Check List](/img/articles/server-checks/screens/03.png)

We check the volumes if they're backed up with the date mentioned.

```bash
function check_aws
{
  whiptail --title "AWS: EC2 Checks" \
    --msgbox "Prepare by going to AWS -> EC2 -> Elastic Block Storage -> Snapshots" 8 78

  # https://en.wikibooks.org/wiki/Bash_Shell_Scripting/Whiptail#Check_list
  # https://stackoverflow.com/a/11087523/5873008
  EC2_INSTANCES_BACKED_UP="$(whiptail --title "EC2 Volume Snapshots" --checklist \
    "Were the following volumes backed up for $(date -d "yesterday 13:00" '+%d/%m/%Y') " 20 78 8 \
    "vol-aaaaaaaaaaaaaaaaa" "Live: A" OFF \
    "vol-bbbbbbbbbbbbbbbbb" "Live: B" OFF \
    "vol-ccccccccccccccccc" "Stage: A" OFF \
    "vol-ddddddddddddddddd" "Stage: B" OFF \
    "vol-eeeeeeeeeeeeeeeee" "Marketing: A" OFF \
    3>&1 1>&2 2>&3
  )"

  logger --tag 'servercheck/aws' "EC2 Backups: Verified: $EC2_INSTANCES_BACKED_UP"

  whiptail --title "EC2 Backups" --yesno "Were any issuses identified?" 8 78 \
    && ec2_backups_more_info \
    || logger --tag 'servercheck/aws' "EC2 Backups: Has no issues"
   
  # for ec2_backuo_more_info, see email_more_info above
  # similar check for RDS omitted
}
```

Once all checks have been carried out, finish with.

```bash
logger --tag 'servercheck' "Done: $(hostname)"
```

---

I also added an alias `sever_check` to `~/.bashrc`, `~/.bash_profile`, `~/.zshrc` or equivalent.
 
```bash
function server_check
{
  bash /var/tasks/server-checks.sh
}
```

It's fairly primitive and possibly over-engineered, but I like it!
