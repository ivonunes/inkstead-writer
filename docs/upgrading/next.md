# Unreleased

<!-- unreleased-intro-start (support/prepare-release.sh drops this block at release) -->
The notes for the next release: everything below is in `main` and ships
together when the version is tagged.
<!-- unreleased-intro-end -->

## Buffer syndication

Posts can now syndicate through Buffer, which reaches X, LinkedIn, Threads, Facebook, Instagram and Pinterest from one account. Set `BUFFER_API_KEY` and add targets that name the network, such as `buffer:x`. See the [Buffer guide](/syndication/buffer/).

Nothing needs to change in an existing site. Targets that name only a provider keep working as before, and Buffer results are recorded nested under `buffer` so other providers' entries are untouched.
