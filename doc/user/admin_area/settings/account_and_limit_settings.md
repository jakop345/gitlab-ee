# Account and limit settings

## Repository size limit

> [Introduced][ee-740] in GitLab Enterprise Edition 8.12.

Repositories within your GitLab instance can grow quickly, especially if you are
using LFS. Their size can grow exponentially and eat up your storage device quite
fast.

In order to avoid this from happening, you can set a hard limit for your
repositories' size. This limit can be set globally, per group, or per project,
with per project limits taking the highest priority.

Only a GitLab administrator can set those limits. Setting the limit to `0` means
there are no restrictions.

These settings can be found within each project's settings, in a group's
settings and in the Application Settings area for the global value
(`/admin/application_settings`).

### Repository size restrictions

When a project has reached its size limit, you will not be able to push to it,
create a new merge request, or merge existing ones. You will still be able to
create new issues, and clone the project though. Uploading LFS objects will
also be denied.

In order to lift these restrictions, the administrator of the GitLab instance
needs to increase the limit on the particular project that exceeded it or you
need to [instruct Git to rewrite changes](#manually-).

### Reducing the repository size using Git

If you exceed the repository size limit, your first thought might be to remove
some data, make a new commit and push back to the repository. Unfortunately,
it's not so easy and that workflow won't work. Deleting files in a commit doesn't
actually reduce the size of the repo since the earlier commits and blobs are
still around. What you need to do is rewrite history with Git's
[`filter-branch` option][gitcsm].

>
**Warning:**
Make sure to first make a copy of your repository since rewriting history will
purge the files and information you are about to delete. Also make sure to
inform any collaborators to not use `pull` after your changes, but use `rebase`.

1. Navigate to your repository:

    ```
    cd my_repository/
    ```

1. Change to the branch you want to remove the big file from:

    ```
    git checkout master
    ```

1. Use `filter-branch` to remove the big file:

    ```
    git filter-branch --force --tree-filter 'rm -f path/to/big_file.mpg' HEAD
    ```

1. Instruct Git to purge the unwanted data:

    ```
    git reflog expire --expire=now --all && git gc --prune=now --aggressive
    ```

1. Lastly, force push to the repository:

    ```
    git push --force origin master
    ```

Your repository should now be below the size limit.

>**Note:**
As an alternative to `filter-branch`, you can use the `bfg` tool with a
command like: `bfg --delete-files path/to/big_file.mpg`. Read the
[BFG Repo-Cleaner][bfg] documentation for more information.

### Current limitations for the repository size check

The very first push of a new project cannot be checked for size as of now, so
the first push will allow you to upload more than the limit dictates, but every
subsequent push will be denied. LFS objects, however, can be checked on first
push and **will** be rejected if the sum of their sizes exceeds the maximum
allowed repository size.

[ee-740]: https://gitlab.com/gitlab-org/gitlab-ee/merge_requests/740
[bfg]: https://rtyley.github.io/bfg-repo-cleaner/
[gitscm]: https://git-scm.com/book/en/v2/Git-Tools-Rewriting-History#The-Nuclear-Option:-filter-branch
