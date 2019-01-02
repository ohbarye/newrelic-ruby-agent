# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic
  module Agent
    class TracerTest < Minitest::Test
      def teardown
        NewRelic::Agent.instance.drop_buffered_data
      end

      def test_tracer_aliases
        state = Tracer.state
        refute_nil state
      end

      def test_current_transaction_with_transaction
        in_transaction do |txn|
          assert_equal txn, Tracer.current_transaction
        end
      end

      def test_current_transaction_without_transaction
        assert_nil Tracer.current_transaction
      end

      def test_tracing_enabled
        NewRelic::Agent.disable_all_tracing do
          in_transaction do
            NewRelic::Agent.disable_all_tracing do
              refute Tracer.tracing_enabled?
            end
            refute Tracer.tracing_enabled?
          end
        end
        assert Tracer.tracing_enabled?
      end

      def test_start_transaction_without_one_already_existing
        assert_nil Tracer.current_transaction

        txn = Tracer.start_transaction(name: "Controller/Blogs/index",
                                       category: :controller)

        assert_equal txn, Tracer.current_transaction

        txn.finish
        assert_nil Tracer.current_transaction
      end

      def test_start_transaction_returns_current_if_aready_in_progress
        in_transaction do |txn1|
          refute_nil Tracer.current_transaction

          txn2 = Tracer.start_transaction(name: "Controller/Blogs/index",
                                         category: :controller)

          assert_equal txn2, txn1
          assert_equal txn2, Tracer.current_transaction
        end
      end

      def test_start_transaction_or_segment_without_active_txn
        assert_nil Tracer.current_transaction

        finishable = Tracer.start_transaction_or_segment(
          name: "Controller/Blogs/index",
          category: :controller
        )

        assert_equal finishable, Tracer.current_transaction

        finishable.finish
        assert_nil Tracer.current_transaction
      end

      def test_start_transaction_or_segment_with_active_txn
        in_transaction do |txn|
          finishable = Tracer.start_transaction_or_segment(
            name: "Middleware/Rack/MyMiddleWare/call",
            category: :middleware
          )

          #todo: Implement current_segment on Tracer
          assert_equal finishable, Tracer.current_transaction.current_segment

          finishable.finish
          refute_nil Tracer.current_transaction
        end

        assert_nil Tracer.current_transaction
      end

      def test_start_transaction_or_segment_mulitple_calls
        f1 = Tracer.start_transaction_or_segment(
          name: "Controller/Rack/Test::App/call",
          category: :rack
        )

        f2 = Tracer.start_transaction_or_segment(
          name: "Middleware/Rack/MyMiddleware/call",
          category: :middleware
        )

        f3 = Tracer.start_transaction_or_segment(
          name: "Controller/blogs/index",
          category: :controller
        )

        f4 = Tracer.start_segment(name: "Custom/MyClass/my_meth")

        f4.finish
        f3.finish
        f2.finish
        f1.finish

        assert_metrics_recorded [
          ["Nested/Controller/Rack/Test::App/call", "Controller/blogs/index"],
          ["Middleware/Rack/MyMiddleware/call",     "Controller/blogs/index"],
          ["Nested/Controller/blogs/index",         "Controller/blogs/index"],
          ["Custom/MyClass/my_meth",                "Controller/blogs/index"],
          "Controller/blogs/index",
          "Nested/Controller/Rack/Test::App/call",
          "Middleware/Rack/MyMiddleware/call",
          "Nested/Controller/blogs/index",
          "Custom/MyClass/my_meth"
        ]
      end

      def test_start_transaction_or_segment_mulitple_calls_with_partial_name
        f1 = Tracer.start_transaction_or_segment(
          partial_name: "Test::App/call",
          category: :rack
        )

        f2 = Tracer.start_transaction_or_segment(
          partial_name: "MyMiddleware/call",
          category: :middleware
        )

        f3 = Tracer.start_transaction_or_segment(
          partial_name: "blogs/index",
          category: :controller
        )

        f3.finish
        f2.finish
        f1.finish

        assert_metrics_recorded [
          ["Nested/Controller/Rack/Test::App/call", "Controller/blogs/index"],
          ["Middleware/Rack/MyMiddleware/call",     "Controller/blogs/index"],
          ["Nested/Controller/blogs/index",         "Controller/blogs/index"],
          "Controller/blogs/index",
          "Nested/Controller/Rack/Test::App/call",
          "Middleware/Rack/MyMiddleware/call",
          "Nested/Controller/blogs/index",
        ]
      end

      def test_start_transaction_with_partial_name
        txn = Tracer.start_transaction(
          partial_name: "Test::App/call",
          category: :rack
        )

        txn.finish

        assert_metrics_recorded ["Controller/Rack/Test::App/call"]
      end

      def test_start_segment_delegates_to_transaction
        name = "Custom/MyClass/myoperation"
        unscoped_metrics = [
          "Custom/Segment/something/all",
          "Custom/Segment/something/allWeb"
        ]
        parent = Tracer.start_segment(name: "parent")
        start_time = Time.now

        Transaction.expects(:start_segment).with(name: name,
                                                 unscoped_metrics: unscoped_metrics,
                                                 parent: parent,
                                                 start_time: start_time)

        Tracer.start_segment(name: name,
                             unscoped_metrics: unscoped_metrics,
                             parent: parent,
                             start_time: start_time)
      end

      def test_start_datastore_segment_delegates_to_transaction
        product         = "MySQL"
        operation       = "INSERT"
        collection      = "blogs"
        host            = "localhost"
        port_path_or_id = "3306"
        database_name   = "blog_app"
        start_time      = Time.now
        parent          = Tracer.start_segment(name: "parent")

        Transaction.expects(:start_datastore_segment)
                   .with(product: product,
                         operation: operation,
                         collection: collection,
                         host: host,
                         port_path_or_id: port_path_or_id,
                         database_name: database_name,
                         start_time: start_time,
                         parent: parent)

        Transaction.start_datastore_segment(product: product,
                                            operation: operation,
                                            collection: collection,
                                            host: host,
                                            port_path_or_id: port_path_or_id,
                                            database_name: database_name,
                                            start_time: start_time,
                                            parent: parent)
      end

      def test_start_external_request_segment_delegates_to_transaction
        library    = "Net::HTTP"
        uri        = "https://docs.newrelic.com"
        procedure  = "GET"
        start_time = Time.now
        parent     = Tracer.start_segment(name: "parent")

        Transaction.expects(:start_external_request_segment)
                   .with(library: library,
                         uri: uri,
                         procedure: procedure,
                         start_time: start_time,
                         parent: parent)

        Transaction.start_external_request_segment(library: library,
                                                   uri: uri,
                                                   procedure: procedure,
                                                   start_time: start_time,
                                                   parent: parent)
      end

      def test_start_message_broker_segment_delegates_to_transaction
        action           = :produce,
        library          = "RabbitMQ"
        destination_type =  :exchange,
        destination_name = "QQ"
        headers          = {foo: "bar"}
        parameters       = {bar: "baz"}
        start_time       = Time.now
        parent           = Tracer.start_segment(name: "parent")

        Transaction.expects(:start_message_broker_segment)
                   .with(action: action,
                         library: library,
                         destination_type: destination_type,
                         destination_name: destination_name,
                         headers: headers,
                         parameters: parameters,
                         start_time: start_time,
                         parent: parent)

        Transaction.start_message_broker_segment(action: action,
                                                 library: library,
                                                 destination_type: destination_type,
                                                 destination_name: destination_name,
                                                 headers: headers,
                                                 parameters: parameters,
                                                 start_time: start_time,
                                                 parent: parent)
      end

      def test_accept_distributed_trace_payload_delegates_to_transaction
        payload = stub(:payload)
        in_transaction do |txn|
          txn.expects(:accept_distributed_trace_payload).with(payload)
          Tracer.accept_distributed_trace_payload(payload)
        end
      end

      def test_create_distributed_trace_payload_delegates_to_transaction
        in_transaction do |txn|
          txn.expects(:create_distributed_trace_payload)
          Tracer.create_distributed_trace_payload
        end
      end
    end
  end
end
