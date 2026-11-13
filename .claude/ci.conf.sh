# .claude/ci.conf.sh: this project's CI for `local-ci <pr>` (on PATH from the shared-mac plugin).
# Pull requests run on this Mac only. Jobs run in a checkout of the commit (CI_SRC).

CI_JOBS=(tests plan ios)    # the check names, one per job

ci_job_tests() {
  tests/run.sh
}

# iPhone and iPad pictures, in the simulator (#43): slower, so a job of its own. It passes,
# saying why, where there's no iOS simulator, mac-sim or AXe.
ci_job_ios() {
  tests/test-ios.sh
}

# The plan's pages agree with GitHub's issues, milestones and board (#31). It reads GitHub, so it
# needs gh signed in; without it, it says so and passes, as the tests are what guard the code.
ci_job_plan() {
  if gh auth status --hostname github.com --active >/dev/null 2>&1; then
    python3 -I bin/docs-kit plan check
  else
    echo "plan: skipped, because gh isn't signed in to GitHub here, so the plan can't be read"
  fi
}
