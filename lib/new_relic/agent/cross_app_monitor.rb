# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'digest'
require 'json'

require 'new_relic/agent/inbound_request_monitor'
require 'new_relic/agent/transaction_state'
require 'new_relic/agent/threading/agent_thread'
require 'new_relic/agent/cross_app_payload'

module NewRelic
  module Agent
    class CrossAppMonitor < InboundRequestMonitor

      NEWRELIC_ID_HEADER      = 'X-NewRelic-ID'
      NEWRELIC_TXN_HEADER     = 'X-NewRelic-Transaction'
      NEWRELIC_APPDATA_HEADER = 'X-NewRelic-App-Data'

      NEWRELIC_ID_HEADER_KEY    = 'HTTP_X_NEWRELIC_ID'.freeze
      NEWRELIC_TXN_HEADER_KEY   = 'HTTP_X_NEWRELIC_TRANSACTION'.freeze
      CONTENT_LENGTH_HEADER_KEY = 'HTTP_CONTENT_LENGTH'.freeze

      def on_finished_configuring(events)
        register_event_listeners(events)
      end

      # Expected sequence of events:
      #   :before_call will save our cross application request id to the thread
      #   :after_call will write our response headers/metrics and clean up the thread
      def register_event_listeners(events)
        NewRelic::Agent.logger.
          debug("Wiring up Cross Application Tracing to events after finished configuring")

        events.subscribe(:before_call) do |env| #THREAD_LOCAL_ACCESS
          if id = decoded_id(env) and should_process_request?(id)
            state = NewRelic::Agent::TransactionState.tl_get

            if (transaction = state.current_transaction)
              transaction_info = referring_transaction_info(state, env)
              transaction.client_cross_app_id = id

              payload = CrossAppPayload.new(transaction, transaction_info)
              transaction.cross_app_payload = payload
            end

            CrossAppTracing.assign_intrinsic_transaction_attributes state
          end
        end

        events.subscribe(:after_call) do |env, (_status_code, headers, _body)| #THREAD_LOCAL_ACCESS
          state = NewRelic::Agent::TransactionState.tl_get

          insert_response_header(state, env, headers)
        end
      end

      def referring_transaction_info(state, request_headers)
        txn_header = request_headers[NEWRELIC_TXN_HEADER_KEY] or return
        deserialize_header(txn_header, NEWRELIC_TXN_HEADER)
      end

      def insert_response_header(state, request_headers, response_headers)
        txn = state.current_transaction
        unless txn.nil? || txn.client_cross_app_id.nil?
          txn.freeze_name_and_execute_if_not_ignored do
            content_length = content_length_from_request(request_headers)
            set_response_headers(txn, response_headers, content_length)
          end
        end
      end

      def should_process_request? id
        return cross_app_enabled? && CrossAppTracing.trusts?(id)
      end

      def cross_app_enabled?
        NewRelic::Agent::CrossAppTracing.cross_app_enabled?
      end

      def set_response_headers(transaction, response_headers, content_length)
        payload = obfuscator.obfuscate(
          transaction.cross_app_payload.build_payload(content_length))
        response_headers[NEWRELIC_APPDATA_HEADER] = payload
      end

      def decoded_id(request)
        encoded_id = request[NEWRELIC_ID_HEADER_KEY]
        return "" if encoded_id.nil?

        obfuscator.deobfuscate(encoded_id)
      end

      def content_length_from_request(request)
        request[CONTENT_LENGTH_HEADER_KEY] || -1
      end

      def hash_transaction_name(identifier)
        Digest::MD5.digest(identifier).unpack("@12N").first & 0xffffffff
      end

      def path_hash(txn_name, seed)
        rotated    = ((seed << 1) | (seed >> 31)) & 0xffffffff
        app_name   = NewRelic::Agent.config.app_names.first
        identifier = "#{app_name};#{txn_name}"
        sprintf("%08x", rotated ^ hash_transaction_name(identifier))
      end
    end
  end
end
