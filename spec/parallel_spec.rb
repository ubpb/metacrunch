describe Metacrunch::Parallel do

  let(:testfile) { "/tmp/metacrunch_spec_parallel" }

  before do
    File.delete(testfile) if File.exists?(testfile)
  end

  it "#each" do
    Metacrunch::Parallel.each(1..100, in_processes: 1) do |number|
      File.open(testfile, "a") { |file| file.write("#{number}\n") }
    end

    count = File.foreach(testfile).inject(0) {|c, line| c+1}

    expect(count).to eq(100)
  end

end
