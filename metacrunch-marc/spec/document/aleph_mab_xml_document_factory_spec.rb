describe Metacrunch::Mab2::AlephMabXmlDocumentFactory do

  it "should parse Aleph MAB XML files" do
    xml      = File.read(File.join(RSpec.root, "assets", "aleph_mab_xml", "file1.xml"))
    factory  = Metacrunch::Mab2::AlephMabXmlDocumentFactory.new(xml)
    document = factory.to_document

    #binding.pry

    expect(document.all_data_fields.count).to be(27)
    expect(document.all_control_fields.count).to be(6)
    expect(document.data_fields("070").count).to be(2)
    expect(document.data_fields("100").first.all_sub_fields.count).to be(3)
    expect(document.data_fields("100").first.sub_fields("p").first.value).not_to be_nil
  end

end
