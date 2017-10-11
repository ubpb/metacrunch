describe Metacrunch::Cli do

  describe "#run" do
    before { ARGV.clear }
    let(:cli) { Metacrunch::Cli.new }

    context "given a job file" do
      it "runs the job file" do
        ARGV << File.join(RSpec.root, "assets", "test.metacrunch")
        expect(cli.run.dsl.instance_variable_get("@job_was_run")).to eq(true)
      end
    end

    context "job file missing" do
      it "shows error and exit" do
        ARGV << ""
        expect {
          expect { cli.run }.to raise_error(SystemExit)
        }.to output(/You need to provide a job file/).to_stdout
      end
    end

    context "job file does't exists" do
      it "shows error and exit" do
        ARGV << "foo.metacrunch"
        expect {
          expect { cli.run }.to raise_error(SystemExit)
        }.to output(/The file .+ doesn't exist./).to_stdout
      end
    end

    context "given the -v option" do
      it "shows the version and exit" do
        ARGV << "-v"
        expect {
          expect { cli.run }.to raise_error(SystemExit)
        }.to output("#{Metacrunch::VERSION}\n").to_stdout
      end
    end

    context "given the --version option" do
      it "shows the version and exit" do
        ARGV << "--version"
        expect {
          expect { cli.run }.to raise_error(SystemExit)
        }.to output("#{Metacrunch::VERSION}\n").to_stdout
      end
    end

    context "given an unknown option" do
      it "shows error, banner and exit" do
        ARGV << "--foo"
        expect {
          expect { cli.run }.to raise_error(SystemExit)
        }.to output(/(Error).*(Usage)/m).to_stdout
      end
    end
  end

end
