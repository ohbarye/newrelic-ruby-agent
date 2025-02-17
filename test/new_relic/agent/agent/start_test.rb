# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

class NewRelic::Agent::Agent::StartTest < Minitest::Test
  require 'new_relic/agent/agent'
  include NewRelic::Agent::Startup
  include NewRelic::Agent::SpecialStartup

  def setup
    @harvester = stub("dummy harvester")
    @harvest_samplers = stub("dummy sampler collection")
  end

  def test_already_started_positive
    dummy_logger = mock
    dummy_logger.expects(:error).with("Agent Started Already!")
    NewRelic::Agent.stubs(:logger).returns(dummy_logger)
    self.expects(:started?).returns(true)
    assert already_started?, "should have already started"
  end

  def test_already_started_negative
    self.expects(:started?).returns(false)
    refute already_started?
  end

  def test_disabled_positive
    with_config(:agent_enabled => false) do
      assert disabled?
    end
  end

  def test_disabled_negative
    with_config(:agent_enabled => true) do
      refute disabled?
    end
  end

  def test_check_config_and_start_agent_disabled
    self.expects(:monitoring?).returns(false)
    check_config_and_start_agent
  end

  def test_check_config_and_start_agent_incorrect_key
    self.expects(:monitoring?).returns(true)
    self.expects(:has_correct_license_key?).returns(false)
    check_config_and_start_agent
  end

  def test_check_config_and_start_agent_forking
    self.expects(:monitoring?).returns(true)
    self.expects(:has_correct_license_key?).returns(true)
    self.expects(:using_forking_dispatcher?).returns(true)
    check_config_and_start_agent
  end

  def test_check_config_and_start_agent_normal
    @harvester.expects(:mark_started)
    @harvest_samplers.expects(:load_samplers)
    self.expects(:start_worker_thread)
    self.expects(:install_exit_handler)
    self.expects(:environment_for_connect)
    with_config(:dispatcher => 'test', :sync_startup => false, :monitor_mode => true,
      :license_key => 'a' * 40, :disable_samplers => false) do
      check_config_and_start_agent
    end
  end

  def test_check_config_and_start_agent_sync
    @harvester.expects(:mark_started)
    @harvest_samplers.expects(:load_samplers)
    self.expects(:connect_in_foreground)
    self.expects(:start_worker_thread)
    self.expects(:install_exit_handler)
    self.expects(:environment_for_connect)
    with_config(:dispatcher => 'test', :sync_startup => true, :monitor_mode => true,
      :license_key => 'a' * 40, :disable_samplers => false) do
      check_config_and_start_agent
    end
  end

  def test_connect_in_foreground
    self.expects(:connect).with({:keep_retrying => false})
    connect_in_foreground
  end

  def at_exit
    yield
  end
  private :at_exit

  def test_install_exit_handler_positive
    self.expects(:sinatra_classic_app?).returns(false)
    # we are overriding at_exit above, to immediately return, so we can
    # test the shutdown logic. It's somewhat unfortunate, but we can't
    # kill the interpreter during a test.
    self.expects(:shutdown)
    with_config(:send_data_on_exit => true) do
      install_exit_handler
    end
  end

  def test_force_install_exit_handler_positive
    self.expects(:sinatra_classic_app?).returns(true)
    # we are overriding at_exit above, to immediately return, so we can
    # test the shutdown logic. It's somewhat unfortunate, but we can't
    # kill the interpreter during a test.
    self.expects(:shutdown)
    with_config(:send_data_on_exit => true, :force_install_exit_handler => true) do
      install_exit_handler
    end
  end

  def test_install_exit_handler_negative
    with_config(:send_data_on_exit => false) do
      install_exit_handler
    end
    # should not raise exception
  end

  def test_force_install_exit_handler_negative
    # forcing exit handler should only install if send_data_on_exit also true!
    with_config(:send_data_on_exit => false, :force_install_exit_handler => true) do
      install_exit_handler
    end
    # should not raise exception
  end

  def test_install_exit_handler_weird_ruby
    with_config(:send_data_on_exit => true) do
      self.expects(:sinatra_classic_app?).returns(true)
      install_exit_handler
    end
  end

  def test_monitoring_positive
    with_config(:monitor_mode => true) do
      assert monitoring?
    end
  end

  def test_monitoring_negative
    with_config(:monitor_mode => false) do
      refute monitoring?
    end
  end

  def test_has_license_key_positive
    with_config(:license_key => 'a' * 40) do
      assert has_license_key?
    end
  end

  def test_has_license_key_negative
    with_config(:license_key => false) do
      refute has_license_key?
    end
  end

  def test_has_correct_license_key_positive
    self.expects(:has_license_key?).returns(true)
    self.expects(:correct_license_length).returns(true)
    assert has_correct_license_key?
  end

  def test_has_correct_license_key_negative
    self.expects(:has_license_key?).returns(false)
    refute has_correct_license_key?
  end

  def test_correct_license_length_positive
    with_config(:license_key => 'a' * 40) do
      assert correct_license_length
    end
  end

  def test_correct_license_length_negative
    with_config(:license_key => 'a' * 30) do
      refute correct_license_length
    end
  end

  def test_using_forking_dispatcher_positive
    with_config(:dispatcher => :passenger) do
      assert using_forking_dispatcher?
    end
  end

  def test_using_forking_dispatcher_negative
    with_config(:dispatcher => :frobnitz) do
      refute using_forking_dispatcher?
    end
  end

  private

  def mocked_control
    fake_control = mock('control')
    self.stubs(:control).returns(fake_control)
    fake_control
  end
end
