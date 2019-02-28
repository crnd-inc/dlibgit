/*
 *             Copyright David Nadlinger 2014.
 *              Copyright Sönke Ludwig 2014.
 *  Distributed under the Boost Software License, Version 1.0.
 *     (See accompanying file LICENSE_1_0.txt or copy at
 *           http://www.boost.org/LICENSE_1_0.txt)
 */
module git.remote;

import git.oid;
import git.repository;
import git.net;
import git.types;
import git.util;
import git.version_;

import deimos.git2.net;
import deimos.git2.oid;
import deimos.git2.remote;
import deimos.git2.strarray;
import deimos.git2.types;

import std.conv : to;
import std.string : toStringz;


string[] listRemotes(GitRepo repo)
{
	git_strarray dst;
	require(git_remote_list(&dst, repo.cHandle) == 0);
	scope (exit) git_strarray_free(&dst);
	auto ret = new string[dst.count];
	foreach (i; 0 .. dst.count)
		ret[i] = dst.strings[i].to!string();
	return ret;
}


///
enum GitDirection
{
    ///
    fetch = GIT_DIRECTION_FETCH,

    ///
    push = GIT_DIRECTION_PUSH
}

///
enum GitRemoteAutotagOption
{
    ///
    automatic = 0,

    ///
    none = 1,

    ///
    all = 2
}

///
enum GitRemoteCompletionType {
    download = GIT_REMOTE_COMPLETION_DOWNLOAD,
    indexing = GIT_REMOTE_COMPLETION_INDEXING,
    error = GIT_REMOTE_COMPLETION_ERROR,
}

///
struct GitRemoteCallbacks {
    void delegate(string str) progress;
    void delegate(GitRemoteCompletionType type) completion;
    //void delegate(GitCred *cred, string url, string username_from_url, uint allowed_types) credentials;
    TransferCallbackDelegate transferProgress;
}

alias GitUpdateTipsDelegate = void delegate(string refname, in ref GitOid a, in ref GitOid b);


///
struct GitRemote
{
    // Internal, see free-standing constructor functions below.
    private this(GitRepo repo, git_remote* remote)
    {
        _repo = repo;
        _data = Data(remote);
    }

    ///
    @property string name() const
    {
        return to!string(git_remote_name(_data._payload));
    }

    ///
    @property string url() const
    {
        return to!string(git_remote_url(_data._payload));
    }

    ///
    @property void name(in char[] url)
    {
        require(git_remote_set_url(_repo.cHandle, git_remote_name(_data._payload), url.gitStr) == 0);
    }

    ///
    @property string pushURL() const
    {
        return to!string(git_remote_pushurl(_data._payload));
    }

    ///
    @property void pushURL(in char[] url)
    {
        require(git_remote_set_pushurl(_repo.cHandle, git_remote_name(_data._payload), url.gitStr) == 0);
    }

    @property GitTransferProgress stats()
    {
        return GitTransferProgress(git_remote_stats(_data._payload));
    }

	@property GitRemoteAutotag autoTag() { return cast(GitRemoteAutotag)git_remote_autotag(this.cHandle); }
	@property void autoTag(GitRemoteAutotag value) { git_remote_set_autotag(_repo.cHandle, git_remote_name(_data._payload), cast(git_remote_autotag_option_t)value); }

    void connect(GitDirection direction)
    {
        require(git_remote_connect(_data._payload, cast(git_direction)direction, null, null, null) == 0);
    }

    ///
    @property bool connected()
    {
        return git_remote_connected(_data._payload) != 0;
    }

    ///
    void stop()
    {
        git_remote_stop(_data._payload);
    }

    ///
    void disconnect()
    {
        git_remote_disconnect(_data._payload);
    }

    ///
    void download(TransferCallbackDelegate progressCallback)
    {
        GitRemoteCallbacks cb;
        cb.transferProgress = progressCallback;
        download(&cb);
    }
    ///
    void download(GitRemoteCallbacks* callbacks = null)
    {
        assert(connected, "Must connect(GitDirection.push) before invoking download().");

        GitRemoteCallbackCTX ctx;
        ctx.cb = callbacks;

        git_remote_callbacks gitcallbacks;
        static if (targetLibGitVersion < VersionInfo(0, 23, 0)) {
            gitcallbacks.progress = &progress_cb;
        }
        gitcallbacks.completion = &completion_cb;
        static if (targetLibGitVersion >= VersionInfo(0, 20, 0)) {
            //gitcallbacks.credentials = &cred_acquire_cb;
            gitcallbacks.transfer_progress = &transfer_progress_cb;
        }
        gitcallbacks.payload = cast(void*)&ctx;

        static if (targetLibGitVersion == VersionInfo(0, 19, 0)) {
            require(git_remote_set_callbacks(_data._payload, &gitcallbacks) == 0);
            require(git_remote_download(_data._payload, &transfer_progress_cb, cast(void*)&ctx) == 0, ctx.ex);
        } else static if (targetLibGitVersion < VersionInfo(0, 23, 0)){
            require(git_remote_set_callbacks(_data._payload, &gitcallbacks) == 0);
            require(git_remote_download(_data._payload) == 0, ctx.ex);
        } else {
            git_fetch_options opts = GIT_FETCH_OPTIONS_INIT;
            opts.callbacks = gitcallbacks;

            require(git_remote_download(_data._payload, null, &opts) == 0, ctx.ex);
        }
        if (ctx.ex) throw ctx.ex;
    }

    void addFetch(string refspec) { require(git_remote_add_fetch(_repo.cHandle, refspec.toStringz, git_remote_name(_data._payload)) == 0); }

    void updateTips(scope void delegate(string refname, in ref GitOid a, in ref GitOid b) updateTips)
    {
        static struct CTX { GitUpdateTipsDelegate updateTips; Exception e; }

        static extern(C) nothrow int update_cb(const(char)* refname, const(git_oid)* a, const(git_oid)* b, void* payload)
        {
            auto ctx = cast(CTX*)payload;
            if (ctx.updateTips) {
                try {
                    auto ac = GitOid(*a);
                    auto bc = GitOid(*b);
                    ctx.updateTips(refname.to!string, ac, bc);
                } catch (Exception e) {
                    ctx.e = e;
                    return -1;
                }
            }
            return 0;
        }

        CTX ctx;
        ctx.updateTips = updateTips;

        git_remote_callbacks gitcallbacks;
        gitcallbacks.update_tips = &update_cb;
        gitcallbacks.payload = &ctx;
        static if (targetLibGitVersion < VersionInfo(0, 23, 0)){
            require(git_remote_set_callbacks(_data._payload, &gitcallbacks) == 0);
            auto ret = git_remote_update_tips(_data._payload);
        } else {
            auto ret = git_remote_update_tips(_data._payload, &gitcallbacks, 1, GIT_REMOTE_DOWNLOAD_TAGS_UNSPECIFIED, null);
        }
        if (ctx.e) throw ctx.e;
        require(ret == 0);
    }

    immutable(GitRemoteHead)[] ls()
    {
        static if (targetLibGitVersion == VersionInfo(0, 19, 0)) {
            static struct CTX { immutable(GitRemoteHead)[] heads; }

            static extern(C) int callback(git_remote_head* rhead, void* payload) {
                auto ctx = cast(CTX*)payload;
                ctx.heads ~= GitRemoteHead(rhead);
                return 0;
            }

            CTX ctx;
            require(git_remote_ls(this.cHandle, &callback, &ctx) == 0);
            return ctx.heads;
        } else {
            const(git_remote_head)** heads;
            size_t head_count;
            require(git_remote_ls(&heads, &head_count, _data._payload) == 0);
            auto ret = new GitRemoteHead[head_count];
            foreach (i, ref rh; ret) ret[i] = GitRemoteHead(heads[i]);
            return cast(immutable)ret;
        }
    }

    mixin RefCountedGitObject!(git_remote, git_remote_free);
    // Reference to the parent repository to keep it alive.
    private GitRepo _repo;
}

///
GitRemote createRemote(GitRepo repo, in char[] name, in char[] url)
{
    git_remote* result;
    require(git_remote_create(&result, repo.cHandle, name.gitStr, url.gitStr) == 0);
    return GitRemote(repo, result);
}

///
GitRemote lookupRemote(GitRepo repo, in char[] name)
{
    git_remote* result;
    require(git_remote_lookup(&result, repo.cHandle, name.gitStr) == 0);
    return GitRemote(repo, result);
}


private extern(C) nothrow {
    static if (targetLibGitVersion == VersionInfo(0, 19, 0)) {
        void progress_cb(const(char)* str, int len, void* payload)
        {
            auto ctx = cast(GitRemoteCallbackCTX*)payload;
            if (ctx.cb && ctx.cb.progress) {
                try ctx.cb.progress(str[0 .. len].idup);
                catch (Exception e) {
                    ctx.ex = e;
                }
            }
        }
    } else {
        int progress_cb(const(char)* str, int len, void* payload)
        {
            auto ctx = cast(GitRemoteCallbackCTX*)payload;
            if (ctx.cb && ctx.cb.progress) {
                try ctx.cb.progress(str[0 .. len].idup);
                catch (Exception e) {
                    ctx.ex = e;
                    return -1;
                }
            }
            return 0;
        }
    }

    /*int cred_acquire_cb(git_cred** dst, const(char)* url, const(char)* username_from_url, uint allowed_types, void* payload)
    {
        auto ctx = cast(GitRemoteCallbackCTX)payload;
        try ctx.cb.credentials(...);
        catch (Exception e) {
            ctx.ex = e;
            return -1;
        }
        return 0;
    }*/

    int completion_cb(git_remote_completion_type type, void* payload)
    {
        auto ctx = cast(GitRemoteCallbackCTX*)payload;
        if (ctx.cb && ctx.cb.completion) {
            try ctx.cb.completion(cast(GitRemoteCompletionType)type);
            catch (Exception e) {
                ctx.ex = e;
                return -1;
            }
        }
        return 0;
    }

    int transfer_progress_cb(const(git_transfer_progress)* stats, void* payload)
    {
        auto ctx = cast(GitRemoteCallbackCTX*)payload;
        if (ctx.cb && ctx.cb.transferProgress) {
            try {
                auto tp = GitTransferProgress(stats);
                ctx.cb.transferProgress(tp);
            } catch (Exception e) {
                ctx.ex = e;
                return -1;
            }
        }
        return 0;
    }
}

enum GitRemoteAutotag {
	auto_ = GIT_REMOTE_DOWNLOAD_TAGS_AUTO,
	none = GIT_REMOTE_DOWNLOAD_TAGS_NONE,
	all = GIT_REMOTE_DOWNLOAD_TAGS_ALL
}

private struct GitRemoteCallbackCTX {
    GitRemoteCallbacks* cb;
    Exception ex;
}

/+ TODO: Port these.

alias git_remote_rename_problem_cb = int function(const(char)* problematic_refspec, void *payload);

int git_remote_get_fetch_refspecs(git_strarray *array, git_remote *remote);

int git_remote_add_push(git_remote *remote, const(char)* refspec);

int git_remote_get_push_refspecs(git_strarray *array, git_remote *remote);

void git_remote_clear_refspecs(git_remote *remote);

size_t git_remote_refspec_count(git_remote *remote);

const(git_refspec)* git_remote_get_refspec(git_remote *remote, size_t n);

int git_remote_remove_refspec(git_remote *remote, size_t n);

int git_remote_valid_url(const(char)* url);

int git_remote_supported_url(const(char)* url);

void git_remote_check_cert(git_remote *remote, int check);

void git_remote_set_cred_acquire_cb(
    git_remote *remote,
    git_cred_acquire_cb cred_acquire_cb,
    void *payload);

int git_remote_set_transport(
    git_remote *remote,
    git_transport *transport);

enum git_remote_completion_type {
    GIT_REMOTE_COMPLETION_DOWNLOAD,
    GIT_REMOTE_COMPLETION_INDEXING,
    GIT_REMOTE_COMPLETION_ERROR,
} ;

mixin _ExportEnumMembers!git_remote_completion_type;

struct git_remote_callbacks {
    uint version_ = GIT_REMOTE_CALLBACKS_VERSION;
    void function(const(char)* str, int len, void *data) progress;
    int function(git_remote_completion_type type, void *data) completion;
    int function(const(char)* refname, const(git_oid)* a, const(git_oid)* b, void *data) update_tips;
    void *payload;
}

enum GIT_REMOTE_CALLBACKS_VERSION = 1;
enum git_remote_callbacks GIT_REMOTE_CALLBACKS_INIT = { GIT_REMOTE_CALLBACKS_VERSION };

int git_remote_set_callbacks(git_remote *remote, git_remote_callbacks *callbacks);

const(git_transfer_progress)*  git_remote_stats(git_remote *remote);



int git_remote_rename(
    git_remote *remote,
    const(char)* new_name,
    git_remote_rename_problem_cb callback,
    void *payload);

int git_remote_update_fetchhead(git_remote *remote);

void git_remote_set_update_fetchhead(git_remote *remote, int value);

int git_remote_is_valid_name(const(char)* remote_name);

+/
