# What a shared test environment would look like.
environment              = "nonprod"
deletion_protection      = true
force_destroy_buckets    = false
enable_waf               = true
enable_guardrail         = true
enable_object_lock       = true
object_lock_mode         = "GOVERNANCE"
enable_dr_replication    = true
recording_retention_days = 365
archive_transition_days  = 90
