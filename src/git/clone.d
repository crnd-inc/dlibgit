/*
 *             Copyright David Nadlinger 2014.
 *  Distributed under the Boost Software License, Version 1.0.
 *     (See accompanying file LICENSE_1_0.txt or copy at
 *           http://www.boost.org/LICENSE_1_0.txt)
 */
module git.clone;

import git.checkout;
import git.credentials;
import git.remote;
import git.repository;
import git.transport;
import git.types;
import git.util;
import git.version_;

import deimos.git2.clone;
import deimos.git2.remote;
import deimos.git2.transport;
import deimos.git2.types;

///
struct GitCloneOptions
{
    uint version_ = git_clone_options.init.version_;

    GitCheckoutOptions checkoutOptions;

    bool cloneBare;

    static if (targetLibGitVersion == VersionInfo(0, 19, 0)) TransferCallbackDelegate fetchProgessCallback;

    static if (targetLibGitVersion == VersionInfo(0, 19, 0)) {
        string pushURL;
        string fetchSpec;
        string pushSpec;

        GitCredAcquireDelegate credAcquireCallback;

        GitTransportFlags transportFlags;
        // GitTransport transport; // TODO: translate
        // GitRemoteCallback[] remoteCallbacks; // TODO: implement translation
        GitRemoteAutotagOption remoteAutotag;
    }
    string checkoutBranch;
}


static if (targetLibGitVersion == VersionInfo(0, 19, 0))  {
    extern(C) nothrow int cFetchProgessCallback(
        const(git_transfer_progress)* stats,
        void* payload)
    {
        auto dg = (cast(GitCloneOptions*)payload).fetchProgessCallback;
        if (dg) {
            try {
                auto tp = GitTransferProgress(stats);
                dg(tp);
            } catch (Exception e) {
                return -1;
            }
        }
        return 0;
    }

    extern(C) int cCredAcquireCallback(
        git_cred** cred,
        const(char)* url,
        const(char)* username_from_url,
        uint allowed_types,
        void* payload)
    {
        auto dg = (cast(GitCloneOptions*)payload).credAcquireCallback;
        if (dg)
        {
            auto dCred = dg(toSlice(url), toSlice(username_from_url), allowed_types);
            // FIXME: cred will probably be immediately freed.
            *cred = dCred.cHandle;
            return 0;
        }

        // FIXME: Use real error code here.
        return 1;
    }
}

GitRepo cloneRepo(in char[] url, in char[] localPath, GitCloneOptions options = GitCloneOptions.init)
{
    git_clone_options cOpts;
    with (options)
    {
        cOpts.version_ = version_;
        checkoutOptions.toCCheckoutOpts(cOpts.checkout_opts);
        cOpts.bare = cloneBare;
        static if (targetLibGitVersion == VersionInfo(0, 19, 0)) {
            if (fetchProgessCallback)
            {
                cOpts.fetch_progress_cb = &cFetchProgessCallback;
                cOpts.fetch_progress_payload = &cOpts;
            }
        }
        static if (targetLibGitVersion == VersionInfo(0, 19, 0)) {
            cOpts.pushurl = pushURL.gitStr;
            cOpts.fetch_spec = fetchSpec.gitStr;
            cOpts.push_spec = pushSpec.gitStr;
            if (credAcquireCallback)
            {
                cOpts.cred_acquire_cb = &cCredAcquireCallback;
                cOpts.cred_acquire_payload = &cOpts;
            }
            cOpts.transport_flags = transportFlags;
            // cOpts.transport = // TODO: Translate.
            cOpts.remote_autotag = cast(git_remote_autotag_option_t)remoteAutotag;
        }
        cOpts.checkout_branch = checkoutBranch.gitStr;
    }

    git_repository* repo;
    auto errc = git_clone(&repo, url.gitStr, localPath.gitStr, &cOpts);
    require(errc == 0);
    return GitRepo(repo);
}
