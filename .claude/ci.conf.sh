# .claude/ci.conf.sh: this project's CI for `local-ci <pr>` (on PATH from the shared-mac plugin).
# Pull requests run on this Mac only. Jobs run in a checkout of the commit (CI_SRC).

CI_JOBS=(tests)    # the check names, one per job

ci_job_tests() {
  tests/run.sh
}
