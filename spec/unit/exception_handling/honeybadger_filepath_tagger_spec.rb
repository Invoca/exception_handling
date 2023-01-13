# frozen_string_literal: true

require File.expand_path('../../spec_helper',  __dir__)

module ExceptionHandling
  describe HoneybadgerFilepathTagger do
    subject { HoneybadgerFilepathTagger.new(config_hash) }

    context "without config_hash" do
      let(:config_hash) { nil }

      it "raises an ArgumentError" do
        expect { subject }.to raise_error(ArgumentError, "config required for HoneybadgerFilepathTagger")
      end
    end

    context "with config_hash" do
      let(:config_hash) do
        {
          "cereals" => [ # Example showing that the labels can be arbitrary
            "captain_crunch.rb",
            "cocoa_puffs.rb",
            "exception_handling/honeybadger_filepath_tagger_spec",
          ],
          "ivr-campaigns-team" => [
            "exception_handling/honeybadger_filepath_tagger_spec"
          ],
          "gems" => [ # Here to confirm we're ignoring gem paths
            "rspec",
            "bundler",
            "exceptional_synchrony",
            "exception_handling-2.11.3",
            "sidekiq_unique_jobs",
            "sidekiq-unique-jobs"
          ]
        }
      end

      it "returns tags for exception backtraces with matching filepaths" do
        exception = nil
        begin
          raise "Here's a runtime error from within the spec file!"
        rescue => ex
          exception = ex
        end
        expect(subject.matching_tags(exception)).to match_array(["cereals", "ivr-campaigns-team"])
      end

      it "returns empty array for exceptions without a backtrace" do
        exception = ArgumentError.new("example arg error")
        expect(exception.backtrace).to be_nil
        expect(subject.matching_tags(exception)).to match_array([])
      end

      it "does not return tags for filepaths that are not matching (ignoring gem paths) - Ringswitch example" do
        exception = nil
        begin
          raise ArgumentError.new, "example arg error"
        rescue => ex
          exception = ex
        end
        exception.set_backtrace([
          "bundle/ruby/2.7.0/gems/exception_handling-2.11.3/lib/exception_handling.rb:485:in `make_exception'",
          "bundle/ruby/2.7.0/gems/exception_handling-2.11.3/lib/exception_handling.rb:200:in `log_error'",
          "services/ringswitch/lib/ringswitch/call_flow/dpa_command_executor.rb:712:in `prepare_asr_response'",
          "services/ringswitch/lib/ringswitch/call_flow/dpa_command_executor.rb:343:in `play_and_get_match'",
          "services/ringswitch/lib/ringswitch/call_flow/dpa_command_executor.rb:323:in `play_and_interpret_speech'",
          "services/ringswitch/lib/ringswitch/call_flow/dpa_command_executor.rb:297:in `sync_play_and_interpret_response'",
          "services/ringswitch/lib/ringswitch/node_executor/menu.rb:79:in `sync_play_and_get_response'",
          "services/ringswitch/lib/ringswitch/node_executor/menu.rb:40:in `execute'",
          "services/ringswitch/lib/ringswitch/node_executor/base.rb:27:in `sync_run'",
          "services/ringswitch/lib/ringswitch/call_flow/ivr_flow.rb:815:in `run_node'",
          "services/ringswitch/lib/ringswitch/call_flow/ivr_flow.rb:734:in `process_normal_call'",
          "services/ringswitch/lib/ringswitch/call_flow/ivr_flow.rb:461:in `process_call'",
          "services/ringswitch/lib/ringswitch/call_flow/ivr_flow.rb:260:in `new_call'",
          "services/ringswitch/lib/ringswitch/call_flow/deferred.rb:56:in `block in run_callbacks'",
          "services/ringswitch/lib/ringswitch/call_flow/deferred.rb:72:in `block in ensure_safe'",
          "services/ringswitch/lib/ringswitch/logger.rb:77:in `ensure_safe'",
          "services/ringswitch/lib/ringswitch/call_flow/deferred.rb:71:in `ensure_safe'",
          "services/ringswitch/lib/ringswitch/call_flow/deferred.rb:52:in `run_callbacks'",
          "services/ringswitch/lib/ringswitch/call_flow/deferred.rb:46:in `execute'",
          "services/ringswitch/lib/ringswitch/call_flow/deferred.rb:40:in `block in execute_with_next_tick'",
          "bundle/ruby/2.7.0/gems/exception_handling-2.11.3/lib/exception_handling.rb:323:in `ensure_completely_safe'",
          "services/ringswitch/lib/ringswitch/event_machine_proxy.rb:37:in `block in defer_with_next_tick'",
          "bundle/ruby/2.7.0/gems/exceptional_synchrony-1.4.4/lib/exceptional_synchrony/event_machine_proxy.rb:58:in `block (2 levels) in next_tick'",
          "bundle/ruby/2.7.0/gems/exceptional_synchrony-1.4.4/lib/exceptional_synchrony/event_machine_proxy.rb:122:in `block in ensure_completely_safe'",
          "bundle/ruby/2.7.0/gems/exception_handling-2.11.3/lib/exception_handling.rb:323:in `ensure_completely_safe'",
          "bundle/ruby/2.7.0/gems/exceptional_synchrony-1.4.4/lib/exceptional_synchrony/event_machine_proxy.rb:121:in `ensure_completely_safe'",
          "bundle/ruby/2.7.0/gems/exceptional_synchrony-1.4.4/lib/exceptional_synchrony/event_machine_proxy.rb:57:in `block in next_tick'",
          "bundle/ruby/2.7.0/gems/em-synchrony-1.0.6/lib/em-synchrony.rb:115:in `block (2 levels) in next_tick'"
        ])
        expect(subject.matching_tags(exception)).to match_array([])
      end

      it "does not return tags for filepaths that are not matching (ignoring gem paths) - Web example" do
        exception = nil
        begin
          raise ArgumentError.new, "example arg error"
        rescue => ex
          exception = ex
        end
        exception.set_backtrace([
          "active_table_set (4.2.1) lib/active_table_set/extensions/abstract_mysql_adapter_override.rb:13:in `rescue in execute'",
          "active_table_set (4.2.1) lib/active_table_set/extensions/abstract_mysql_adapter_override.rb:6:in `execute'",
          "activerecord (5.2.8.1) lib/active_record/connection_adapters/mysql/database_statements.rb:28:in `execute'",
          "active_table_set (4.2.1) lib/active_table_set/extensions/connection_extension.rb:10:in `execute'",
          "invoca-mysql_improvements (0.2.0) lib/invoca/mysql_improvements/mysql2_adapter_kill_on_timeout_mixin.rb:20:in `execute'",
          "app/models/network.rb:2086:in `block in rank_affiliates'",
          "app/models/network.rb:2082:in `each'",
          "app/models/network.rb:2082:in `rank_affiliates'",
          "activerecord (5.2.8.1) lib/active_record/relation/batches.rb:70:in `block (2 levels) in find_each'",
          "activerecord (5.2.8.1) lib/active_record/relation/batches.rb:70:in `each'",
          "activerecord (5.2.8.1) lib/active_record/relation/batches.rb:70:in `block in find_each'",
          "activerecord (5.2.8.1) lib/active_record/relation/batches.rb:136:in `block in find_in_batches'",
          "activerecord (5.2.8.1) lib/active_record/relation/batches.rb:238:in `block in in_batches'",
          "activerecord (5.2.8.1) lib/active_record/relation/batches.rb:222:in `loop'",
          "activerecord (5.2.8.1) lib/active_record/relation/batches.rb:222:in `in_batches'",
          "activerecord (5.2.8.1) lib/active_record/relation/batches.rb:135:in `find_in_batches'",
          "activerecord (5.2.8.1) lib/active_record/relation/batches.rb:69:in `find_each'",
          "activerecord (5.2.8.1) lib/active_record/querying.rb:11:in `find_each'",
          "app/models/network.rb:2078:in `rank_affiliates'",
          "app/models/affiliate.rb:761:in `block (2 levels) in update_statistics'",
          "app/models/change_history/operator_registry.rb:34:in `block in with_operator'",
          "app/models/change_history/operator_registry.rb:50:in `stash_and_then_restore_previous_operator'",
          "app/models/change_history/operator_registry.rb:32:in `with_operator'",
          "app/models/change_history/operator_registry.rb:39:in `with_invoca_system_operator'",
          "app/models/affiliate.rb:757:in `block in update_statistics'",
          "active_table_set (4.2.1) lib/active_table_set/connection_manager.rb:50:in `ensure_safe_cleanup'",
          "active_table_set (4.2.1) lib/active_table_set/connection_manager.rb:64:in `using'",
          "active_table_set (4.2.1) lib/active_table_set.rb:114:in `using'",
          "app/models/affiliate.rb:756:in `update_statistics'",
          "(eval):1:in `block (2 levels) in perform'",
          "app/workers/worker_groups/superworker.rb:40:in `eval'",
          "app/workers/worker_groups/superworker.rb:40:in `block (2 levels) in perform'",
          "app/workers/worker_groups/superworker.rb:62:in `block in with_metrics'",
          "invoca-metrics (2.1.0) lib/invoca/metrics/prometheus/declare_metrics/histogram.rb:40:in `block in time'",
          "/usr/local/lib/ruby/2.7.0/benchmark.rb:308:in `realtime'",
          "invoca-metrics (2.1.0) lib/invoca/metrics/prometheus/declare_metrics/histogram.rb:40:in `time'",
          "app/workers/worker_groups/superworker.rb:62:in `with_metrics'",
          "app/workers/worker_groups/superworker.rb:40:in `block in perform'",
          "app/workers/worker_groups/superworker.rb:55:in `block in with_appropriate_error_handling'",
          "exception_handling (2.13.0) lib/exception_handling.rb:323:in `ensure_safe'",
          "app/workers/worker_groups/superworker.rb:55:in `with_appropriate_error_handling'",
          "app/workers/worker_groups/superworker.rb:39:in `perform'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:187:in `execute_job'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:169:in `block (2 levels) in process'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:128:in `block in invoke'",
          "lib/sidekiq_setup/unique_jobs_enforcer.rb:17:in `block in call'",
          "sidekiq (5.1.3) lib/sidekiq.rb:95:in `block in redis'",
          "connection_pool (2.2.5) lib/connection_pool.rb:63:in `block (2 levels) in with'",
          "connection_pool (2.2.5) lib/connection_pool.rb:62:in `handle_interrupt'",
          "connection_pool (2.2.5) lib/connection_pool.rb:62:in `block in with'",
          "connection_pool (2.2.5) lib/connection_pool.rb:59:in `handle_interrupt'",
          "connection_pool (2.2.5) lib/connection_pool.rb:59:in `with'",
          "sidekiq (5.1.3) lib/sidekiq.rb:92:in `redis'",
          "lib/sidekiq_setup/middleware_helpers.rb:15:in `redis'",
          "lib/sidekiq_setup/unique_jobs_enforcer.rb:13:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:130:in `block in invoke'",
          "lib/sidekiq_setup/middleware/change_history_operator.rb:22:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:130:in `block in invoke'",
          "contextual_logger (1.1.1) lib/contextual_logger.rb:57:in `with_context'",
          "lib/sidekiq_setup/middleware/logging.rb:15:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:130:in `block in invoke'",
          "lib/sidekiq_setup/middleware/metrics.rb:220:in `block in call'",
          "/usr/local/lib/ruby/2.7.0/benchmark.rb:293:in `measure'",
          "lib/sidekiq_setup/middleware/metrics.rb:220:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:130:in `block in invoke'",
          "lib/sidekiq_setup/middleware/memory_check.rb:13:in `block in call'",
          "lib/sidekiq_setup/middleware/memory_check.rb:30:in `log_job_memory_usage'",
          "lib/sidekiq_setup/middleware/memory_check.rb:13:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:130:in `block in invoke'",
          "sidekiq-pro (4.0.2) lib/sidekiq/batch/middleware.rb:56:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:130:in `block in invoke'",
          "sidekiq-superworker (1.2.1) lib/sidekiq/superworker/server/middleware.rb:11:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:130:in `block in invoke'",
          "sidekiq-unique-jobs (5.0.10) lib/sidekiq_unique_jobs/lock/until_executed.rb:63:in `after_yield_yield'",
          "sidekiq-unique-jobs (5.0.10) lib/sidekiq_unique_jobs/lock/until_executed.rb:20:in `execute'",
          "sidekiq-unique-jobs (5.0.10) lib/sidekiq_unique_jobs/server/middleware.rb:18:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:130:in `block in invoke'",
          "lib/sidekiq_setup/middleware/queue_overrides.rb:24:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:130:in `block in invoke'",
          "sidekiq (5.1.3) lib/sidekiq/middleware/chain.rb:133:in `invoke'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:168:in `block in process'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:139:in `block (6 levels) in dispatch'",
          "sidekiq (5.1.3) lib/sidekiq/job_retry.rb:98:in `local'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:138:in `block (5 levels) in dispatch'",
          "sidekiq (5.1.3) lib/sidekiq/rails.rb:42:in `block in call'",
          "activesupport (5.2.8.1) lib/active_support/execution_wrapper.rb:90:in `wrap'",
          "activesupport (5.2.8.1) lib/active_support/reloader.rb:73:in `block in wrap'",
          "activesupport (5.2.8.1) lib/active_support/execution_wrapper.rb:90:in `wrap'",
          "activesupport (5.2.8.1) lib/active_support/reloader.rb:72:in `wrap'",
          "sidekiq (5.1.3) lib/sidekiq/rails.rb:41:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:134:in `block (4 levels) in dispatch'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:199:in `stats'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:129:in `block (3 levels) in dispatch'",
          "sidekiq (5.1.3) lib/sidekiq/job_logger.rb:8:in `call'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:128:in `block (2 levels) in dispatch'",
          "sidekiq (5.1.3) lib/sidekiq/job_retry.rb:73:in `global'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:127:in `block in dispatch'",
          "sidekiq (5.1.3) lib/sidekiq/logging.rb:48:in `with_context'",
          "sidekiq (5.1.3) lib/sidekiq/logging.rb:42:in `with_job_hash_context'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:126:in `dispatch'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:167:in `process'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:85:in `process_one'",
          "sidekiq (5.1.3) lib/sidekiq/processor.rb:73:in `run'",
          "sidekiq (5.1.3) lib/sidekiq/util.rb:16:in `watchdog'",
          "sidekiq (5.1.3) lib/sidekiq/util.rb:25:in `block in safe_thread'"
        ])
        expect(subject.matching_tags(exception)).to match_array([])
      end
    end
  end
end
