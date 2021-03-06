#
# Cookbook Name:: chef_server
# Spec:: setup
#
# The MIT License (MIT)
#
# Copyright (c) 2016 sweeper.io
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

describe "chef_server::setup" do
  cached(:chef_run) do
    runner = Runner.new(config)
    runner.converge(described_recipe)
  end

  it "converges successfully" do
    expect { chef_run }.to_not raise_error
  end

  it "creates a user for each one defined in data.yml" do
    properties = %w(first_name last_name email password)

    config.users.each do |user|
      data = properties.each_with_object({}) { |key, hash| hash[key] = user[key] }
      data.merge!(output_dir: config.path)

      expect(chef_run).to create_chef_server_user(user.username).with(data)
    end
  end

  it "creates an org based on data from data.yml" do
    expect(chef_run).to create_chef_server_org(config.org.name).with(
      full_name: config.org.full_name,
      users: config.org.users,
      output_dir: config.path
    )
  end

  context "when stepping into user resource" do
    let(:chef_run) do
      runner = Runner.new(config, step_into: %w(chef_server_user))
      runner.converge(described_recipe)
    end

    describe "and users do not exist" do
      before(:each) do
        stub_command(/\Achef-server-ctl user-list | grep '.*'\z/).and_return(false)
      end

      it "executes `create chef user: <username>` for each user" do
        config.users.each do |user|
          expect(chef_run).to run_execute("create chef user #{user.username}")
        end
      end
    end

    describe "and users already exist" do
      before(:each) do
        stub_command(/\Achef-server-ctl user-list | grep '.*'\z/).and_return(true)
      end

      it "does not execute `create chef user: <username>` for each user" do
        config.users.each do |user|
          expect(chef_run).to_not run_execute("create chef user #{user.username}")
        end
      end
    end
  end

  context "when stepping into org resource" do
    let(:chef_run) do
      runner = Runner.new(config, step_into: %w(chef_server_org))
      runner.converge(described_recipe)
    end

    let(:shell) do
      shell = double("shell_out double")
      allow(shell).to receive(:run_command)
      allow(shell).to receive(:exitstatus).and_return(status)
      allow(shell).to receive(:live_stream)
      allow(shell).to receive(:live_stream=)

      shell
    end

    before(:each) do
      command = "chef-server-ctl org-list | grep '#{config.org.name}'"
      expect(Mixlib::ShellOut).to receive(:new).with(command, anything).and_return(shell)
    end

    describe "and the organization does not exist" do
      let(:status) { 1 }

      it "creates the organization" do
        expect(chef_run).to run_execute("create chef organization")
      end

      it "associates admin users with the org" do
        config.org.users["admins"].each do |admin|
          expect(chef_run).to run_execute("associate #{admin} with the #{config.org.name} org")
        end
      end

      it "associates regular users with the org" do
        config.org.users["users"].each do |admin|
          expect(chef_run).to run_execute("associate #{admin} with the #{config.org.name} org")
        end
      end
    end

    describe "and the organization exists" do
      let(:status) { 0 }

      it "doesn't create the organization" do
        expect(chef_run).to_not run_execute("create chef organization")
      end

      it "doesn't associate any users with the org" do
        users = config.org.users["admins"] + config.org.users["users"]
        users.each do |admin|
          expect(chef_run).to_not run_execute("associate #{admin} with the #{config.org.name} org")
        end
      end
    end
  end
end
