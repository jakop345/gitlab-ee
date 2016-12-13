# Extra Sidekiq Processes

GitLab Enterprise Edition allows one to start an extra set of Sidekiq processes
besides the default one. These processes can be used to consume a dedicated set
of queues. This can be used to ensure certain queues always have dedicated
workers, no matter the amount of jobs that need to be processed.

## Starting Extra Processes

Starting extra Sidekiq processes can be done using the command
`bin/sidekiq-cluster`. This command takes arguments using the following syntax:

```bash
sidekiq-cluster [QUEUE,QUEUE,...] [QUEUE, ...]
```

Each separate argument denotes a group of queues that have to be processed by a
Sidekiq process. Multiple queues can be processed by the same process by
separating them with a comma instead of a space.

For example, say you want to start 2 extra processes: one to process the
"process_commit" queue, and one to process the "post_receive" queue. This can be
done as follows:

```bash
sidekiq-cluster process_commit post_receive
```

If you instead want to start one process processing both queues you'd use the
following syntax:

```bash
sidekiq-cluster process_commit,post_receive
```

If you want to have one Sidekiq process process the "process_commit" and
"post_receive" queues, and one process to process the "gitlab_shell" queue,
you'd use the following:

```bash
sidekiq-cluster process_commit,post_receive gitlab_shell
```

## Concurrency

Each process started using `sidekiq-cluster` starts with a number of threads
that equals the number of queues, plus one spare thread. For example, a process
that processes "process_commit" and "post_receive" will use 3 threads in total.

## Monitoring

The `sidekiq-cluster` command will not terminate once it has started the desired
amount of Sidekiq processes. Instead the process will continue running and
forward any signals to the child processes. This makes it easy to stop all
Sidekiq processes as you simply send a signal to the `sidekiq-cluster` process,
instead of having to send it to the individual processes.

If the `sidekiq-cluster` process crashes or is SIGKILL'd the child processes
will terminate themselves after a few seconds. This ensures you don't end up
with zombie Sidekiq processes.

All of this makes monitoring the processes fairly easy. Simply hook up
`sidekiq-cluster` to your supervisor of choice (e.g. runit) and you're good to
go.

If a child process died the `sidekiq-cluster` command will signal all remaining
process to terminate, then terminate itself. This removes the need for
`sidekiq-cluster` to re-implement complex process monitoring/restarting code.
Instead you should make sure your supervisor restarts the `sidekiq-cluster`
process whenever necessary.

## PID Files

The `sidekiq-cluster` command can store its PID in a file. By default no PID
file is written, but this can be changed by passing the `--pidfile` option to
`sidekiq-cluster`. For example:

```bash
sidekiq-cluster --pidfile /var/run/gitlab/sidekiq_cluster.pid process_commit
```

Keep in mind that the PID file will contain the PID of the `sidekiq-cluster`
command, and not the PID(s) of the started Sidekiq processes.

## Environment

The Rails environment can be set by passing the `--environment` flag to the
`sidekiq-cluster` command, or by setting `RAILS_ENV` to a non-empty value. The
default value is "development".
