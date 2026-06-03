extension InksteadWriterCLI {
static var initHelp: String {
        """
        Usage: inkstead-writer init [directory] [options]

        Options:
          --ci github-actions|gitlab-ci|forgejo-actions|none
          --deploy cloudflare-workers|github-pages|gitlab-pages|netlify|none
          --deploy-project-name name
          --syndication mastodon,bluesky,flickr|none
          --connection-provider github|gitlab|forgejo
          --connection-repository owner/repo
          --connection-branch branch
          --connection-instance-url url
        """
    }

    static var commandHelp: String {
        """
        Inkstead Writer

        Commands:
          build        Build the current site
          cache        List or clean downloaded Inkstead Writer binaries
          deploy       Deploy an already-built site
          dev          Build and serve the site locally
          doctor       Check site setup
          init         Create a new site
          migrate      Apply site migrations
          new post     Create a new article or note
          publish      Build, deploy, syndicate, and redeploy if needed
          requirements Print required environment variables
          syndicate    Publish posts to configured syndication providers
          theme        Check, format, eject, or serve theme tooling
          update       Download the latest Inkstead Writer and migrate the site (--check, --dry-run, --to version)
          version      Print the Inkstead Writer site format version
        """
    }
}
