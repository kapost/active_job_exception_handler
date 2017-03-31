# ActiveJobExceptionHandler

[![Gem Version](https://badge.fury.io/rb/active_job_exception_handler.svg)](http://badge.fury.io/rb/active_job_exception_handler)

<!-- Tocer[start]: Auto-generated, don't remove. -->

# Table of Contents

- [Features](#features)
- [Screencasts](#screencasts)
- [Requirements](#requirements)
- [Setup](#setup)
- [Usage](#usage)
- [Tests](#tests)
- [Versioning](#versioning)
- [Code of Conduct](#code-of-conduct)
- [Contributions](#contributions)
- [License](#license)
- [History](#history)
- [Credits](#credits)

<!-- Tocer[finish]: Auto-generated, don't remove. -->

# Features

# Screencasts

# Requirements

0. [Ruby 2.4.1](https://www.ruby-lang.org)

# Setup

For a secure install, type the following (recommended):

    gem cert --add <(curl --location --silent /gem-public.pem)
    gem install active_job_exception_handler --trust-policy MediumSecurity

NOTE: A HighSecurity trust policy would be best but MediumSecurity enables signed gem verification
while allowing the installation of unsigned dependencies since they are beyond the scope of this
gem.

For an insecure install, type the following (not recommended):

    gem install active_job_exception_handler

Add the following to your Gemfile:

    gem "active_job_exception_handler"

# Usage

Initialize it like this:

```ruby
class ApplicationJob < ActiveJob::Base

  before_perform :initialize_exception_handler

  def perform(normal:, credentials: {}, spawn_job_id:, exception_handler: default_exception_handler)
    @exception_handler = exception_handler
    initialize_exception_handling

    exception_handler.process! do
      return if skip?
      collector.run run_options
      emitter.flush!
      kapost_client.update_credentials(adapter.updated_tokens) if adapter.refreshed_tokens?
      perform_successful
    end
  end

  protected

  def exception_handler
    @exception_handler ||= ExceptionHandler.new(exception_context: exception_context)
  end

  def exception_context
    ExceptionContext.new(
      source: self.class.name,
      queue: queue_name,
      args: arguments
    )
  end

  def initialize_exception_handling
    # implement this method to define how errors are handled
  end
end
```

And then use it in jobs like this:

```ruby
class MyJob < ApplicationJob

  def perform(...)
    # ...
  end

  protected

  def initialize_exception_handling
    exception_handler.add HTTPServerError, :retryables # Transient HTTP error
    exception_handler.add HTTPAuthenticationError, :unretryables # User credentials are wrong, don't retry
    exception_handler.add HTTPNotFoundError, :ignorables # Page is gone, we don't care anymore
  end

end
```

# Tests

To test, run:

    bundle exec rake

# Versioning

Read [Semantic Versioning](http://semver.org) for details. Briefly, it means:

- Major (X.y.z) - Incremented for any backwards incompatible public API changes.
- Minor (x.Y.z) - Incremented for new, backwards compatible, public API enhancements/fixes.
- Patch (x.y.Z) - Incremented for small, backwards compatible, bug fixes.

# Code of Conduct

Please note that this project is released with a [CODE OF CONDUCT](CODE_OF_CONDUCT.md). By
participating in this project you agree to abide by its terms.

# Contributions

Read [CONTRIBUTING](CONTRIBUTING.md) for details.

# License

Copyright (c) 2017 []().
Read [LICENSE](LICENSE.md) for details.

# History

Read [CHANGES](CHANGES.md) for details.
Built with [Gemsmith](https://github.com/bkuhlmann/gemsmith).

# Credits

Developed by [Paul Sadauskas]() and [Brooke Kuhlmann]() at
[Kapost](www.kapost.com).
