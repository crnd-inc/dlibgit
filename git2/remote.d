module git2.remote;

import git2.common;
import git2.indexer;
import git2.net;
import git2.oid;
import git2.transport;
import git2.types;

extern(C):

alias git_remote_rename_problem_cb = int function(const char *problematic_refspec, void *payload);

enum 
{
    GIT_REMOTE_DOWNLOAD_TAGS_UNSET = 0,
    GIT_REMOTE_DOWNLOAD_TAGS_NONE = 1,
    GIT_REMOTE_DOWNLOAD_TAGS_AUTO = 2,
    GIT_REMOTE_DOWNLOAD_TAGS_ALL = 3
}

enum git_remote_completion_type
{
    GIT_REMOTE_COMPLETION_DOWNLOAD = 0,
    GIT_REMOTE_COMPLETION_INDEXING = 1,
    GIT_REMOTE_COMPLETION_ERROR = 2
}

struct git_remote_callbacks 
{
    uint version_ = GIT_REMOTE_CALLBACKS_VERSION;
    void function(const(char)*, int, void*) progress;
    int function(git_remote_completion_type, void*) completion;
    int function(const(char)*, const(git_oid)*, const(git_oid)*, void*) update_tips;
    void* payload;
}

enum GIT_REMOTE_CALLBACKS_VERSION = 1;

enum git_remote_autotag_option {
    GIT_REMOTE_DOWNLOAD_TAGS_UNSET,
    GIT_REMOTE_DOWNLOAD_TAGS_NONE,
    GIT_REMOTE_DOWNLOAD_TAGS_AUTO,
    GIT_REMOTE_DOWNLOAD_TAGS_ALL
}


git_remote_autotag_option git_remote_autotag(git_remote* remote);
void git_remote_check_cert(git_remote* remote, int check);
int git_remote_connect(git_remote* remote, git_direction direction);
int git_remote_connected(git_remote* remote);
int git_remote_create(git_remote** _out, git_repository* repo, const(char)* name, const(char)* url);
int git_remote_create_inmemory(git_remote** _out, git_repository* repo, const(char)* fetch, const(char)* url);
void git_remote_disconnect(git_remote* remote);
int git_remote_download(git_remote* remote, git_transfer_progress_callback progress_cb, void* payload);
const(git_refspec)* git_remote_fetchspec(const(git_remote)* remote);
void git_remote_free(git_remote* remote);
int git_remote_list(git_strarray* remotes_list, git_repository* repo);
int git_remote_load(git_remote** _out, git_repository* repo, const(char)* name);
int git_remote_ls(git_remote* remote, git_headlist_cb list_cb, void* payload);
const(char)* git_remote_name(const(git_remote)* remote);
const(git_refspec)* git_remote_pushspec(const(git_remote)* remote);
const(char)* git_remote_pushurl(const(git_remote)* remote);
int git_remote_rename(git_remote *remote, const char *new_name, git_remote_rename_problem_cb callback, void *payload);
int git_remote_save(const(git_remote)* remote);
void git_remote_set_autotag(git_remote* remote, git_remote_autotag_option value);
void git_remote_set_callbacks(git_remote* remote, git_remote_callbacks* callbacks);
void git_remote_set_cred_acquire_cb(git_remote *remote, git_cred_acquire_cb cred_acquire_cb, void *payload);
int git_remote_set_fetchspec(git_remote* remote, const(char)* spec);
int git_remote_set_pushspec(git_remote* remote, const(char)* spec);
int git_remote_set_pushurl(git_remote* remote, const(char)* url);
int git_remote_set_transport(git_remote *remote, git_transport *transport);
void git_remote_set_update_fetchhead(git_remote *remote, int value);
int git_remote_set_url(git_remote* remote, const(char)* url);
const(git_transfer_progress)* git_remote_stats(git_remote *remote);
void git_remote_stop(git_remote *remote);
int git_remote_supported_url(const(char)* url);
int git_remote_update_fetchhead(git_remote *remote);
int git_remote_update_tips(git_remote* remote);
const(char)* git_remote_url(const(git_remote)* remote);
int git_remote_valid_url(const(char)* url);