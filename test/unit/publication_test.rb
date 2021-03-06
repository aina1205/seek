require 'test_helper'

class PublicationTest < ActiveSupport::TestCase
  
  fixtures :all

  test "event association" do
    publication = Factory :publication
    assert publication.events.empty?
    event = events(:event_with_no_files)
    User.with_current_user(publication.contributor) do
      publication.events << event
      assert publication.valid?
      publication.save!
    end
    publication = Publication.find(publication.id)
    assert_equal 1, publication.events.count
  end

  test "to_rdf" do
    object = Factory :publication
    Factory :relationship, :subject=>Factory(:assay), :other_object=>object, :predicate=>Relationship::RELATED_TO_PUBLICATION
    object.reload

    rdf = object.to_rdf

    RDF::Reader.for(:rdfxml).new(rdf) do |reader|
      assert reader.statements.count >= 1
      assert_equal RDF::URI.new("http://localhost:3000/publications/#{object.id}"), reader.statements.first.subject
    end
  end

  test "content blob search terms" do
    p = Factory :publication
    assert_equal [],p.content_blob_search_terms
  end

  test "assay association" do
    publication = publications(:pubmed_2)
    assay = assays(:modelling_assay_with_data_and_relationship)
    User.current_user = assay.contributor.user
    assay_asset = assay_assets(:metabolomics_assay_asset1)
    assert_not_equal assay_asset.asset, publication
    assert_not_equal assay_asset.assay, assay
    assay_asset.asset = publication
    assay_asset.assay = assay
    User.with_current_user(assay.contributor.user) {assay_asset.save!}
    assay_asset.reload
    assert assay_asset.valid?
    assert_equal assay_asset.asset, publication
    assert_equal assay_asset.assay, assay

  end

  test "publication date from pubmed" do
    mock_pubmed(:content_file=>"pubmed_21533085.txt")
    result = Bio::MEDLINE.new(Bio::PubMed.efetch(21533085).first).reference
    assert_equal '2011/04/20',result.published_date

    mock_pubmed(:content_file=>"pubmed_1.txt")
    result = Bio::MEDLINE.new(Bio::PubMed.efetch(1).first).reference
    assert_equal "1975/06/01",result.published_date

    mock_pubmed(:content_file=>"pubmed_20533085.txt")
    result = Bio::MEDLINE.new(Bio::PubMed.efetch(20533085).first).reference
    assert_equal "2010/06/09",result.published_date
    assert_nil result.error
  end

  test "unknown pubmed_id" do
    mock_pubmed(:content_file=>"pubmed_not_found.txt")
    result = Bio::MEDLINE.new(Bio::PubMed.efetch(1111111111111).first).reference
    assert_equal "No publication could be found on PubMed with that ID",result.error
  end



  test "book chapter doi" do
    mock_crossref(:email=>"fred@email.com",:doi=>"10.1007/978-3-642-16239-8_8",:content_file=>"cross_ref1.xml")
    query=DoiQuery.new("fred@email.com")
    result = query.fetch("10.1007/978-3-642-16239-8_8")
    assert_equal 3,result.publication_type
    assert_equal "Prediction with Confidence Based on a Random Forest Classifier",result.title
    assert_equal 2,result.authors.size
    last_names = ["Devetyarov","Nouretdinov"]
    result.authors.each do |auth|
      assert last_names.include? auth.last_name
    end
    
    assert_equal "Artificial Intelligence Applications and Innovations",result.journal
    assert_equal Date.parse("1 Jan 2010"),result.date_published
    assert_equal "10.1007/978-3-642-16239-8_8",result.doi
    assert_nil result.error

  end

  test "doi with not resolvable error" do
    mock_crossref(:email=>"fred@email.com",:doi=>"10.4230/OASIcs.GCB.2012.1",:content_file=>"cross_ref_no_resolve.xml")
    query=DoiQuery.new("fred@email.com")
    result = query.fetch("10.4230/OASIcs.GCB.2012.1")
    assert_equal "The DOI could not be resolved",result.error
    assert_equal "10.4230/OASIcs.GCB.2012.1",result.doi
  end

  test "malformed doi" do
    mock_crossref(:email=>"fred@email.com",:doi=>"10.1.11.1",:content_file=>"cross_ref_malformed_doi.xml")
    query=DoiQuery.new("fred@email.com")
    result = query.fetch("10.1.11.1")
    assert_equal "Not a valid DOI",result.error
    assert_equal "10.1.11.1",result.doi
  end

  test "editor should not be author" do
    mock_crossref(:email=>"fred@email.com",:doi=>"10.1371/journal.pcbi.1002352",:content_file=>"cross_ref2.xml")
    query=DoiQuery.new("fred@email.com")
    result = query.fetch("10.1371/journal.pcbi.1002352")
    assert result.error.nil?, "There should not be an error"
    assert !result.authors.collect{|auth| auth.last_name}.include?("Papin")
    assert_equal 5,result.authors.size
    assert_nil result.error
  end

  test "model and datafile association" do
    publication = publications(:pubmed_2)
    assert publication.related_models.include?(models(:teusink))
    assert publication.related_data_files.include?(data_files(:picture))
  end

  test "test uuid generated" do
    x = publications(:one)
    assert_nil x.attributes["uuid"]
    x.save    
    assert_not_nil x.attributes["uuid"]
  end

  test "sort by published_date" do
    assert_equal Publication.find(:all).sort_by { |p| p.published_date}.reverse, Publication.default_order
  end

  test "title trimmed" do
    x = Factory :publication, :title => " a pub"
    assert_equal("a pub",x.title)
  end

  test "validation" do
    project = Factory :project
    asset=Publication.new :title=>"fred",:projects=>[project],:doi=>"111"
    assert asset.valid?

    asset=Publication.new :title=>"fred",:projects=>[project],:pubmed_id=>"111"
    assert asset.valid?

    asset=Publication.new :title=>"fred",:projects=>[project]
    assert !asset.valid?

    asset=Publication.new :projects=>[project],:doi=>"111"
    assert !asset.valid?

    asset=Publication.new :title=>"fred",:doi=>"111"
    assert asset.valid?

    #cant have both a pubmed and doi
    asset = Publication.new :title=>"bob",:doi=>"777",:projects=>[project]
    assert asset.valid?
    asset.pubmed_id="999"
    assert !asset.valid?
    asset.doi=nil
    assert asset.valid?
  end
  
  test "creators order is returned in the order they were added" do
    p=Factory :publication
    assert_equal 0,p.creators.size
    
    p1=Factory(:person)
    p2=Factory(:person)
    p3=Factory(:person)
    p4=Factory(:person)


    User.with_current_user(p.contributor) do

      if Seek::Config.is_virtualliver
        [p1,p2,p3,p4].each_with_index do|author, index|
          p.publication_authors.create :person_id=>author.id, :first_name => author.first_name, :last_name=>author.last_name, :author_index => index
        end
      else
        p.creators << p1
        p.creators << p2
        p.creators << p3
        p.creators << p4
      end
      p.save!
      assert_equal 4,p.creators.size
      assert_equal [p1,p2,p3,p4],p.creators
    end

  end
  
  test "uuid doesn't change" do
    x = publications(:one)
    x.save
    uuid = x.attributes["uuid"]
    x.save
    assert_equal x.uuid, uuid
  end
  
  def test_project_not_required
    p=Publication.new(:title=>"blah blah blah",:pubmed_id=>"123")
    assert p.valid?
  end

  test 'validate uniqueness of pubmed_id and doi' do
      project1=Factory :project
      pub=Publication.new(:title=>"test1",:pubmed_id=>"1234", :projects => [project1])
      assert pub.valid?
      assert pub.save
      pub=Publication.new(:title=>"test2",:pubmed_id=>"1234", :projects => [project1])
      assert !pub.valid?

      #unique pubmed_id and doi not only in one project
      as_virtualliver do
         pub=Publication.new(:title=>"test2",:pubmed_id=>"1234", :projects => [Factory(:project)])
         assert !pub.valid?
      end

      pub=Publication.new(:title=>"test3",:doi=>"1234", :projects => [project1])
      assert pub.valid?
      assert pub.save
      pub=Publication.new(:title=>"test4",:doi=>"1234", :projects => [project1])
      assert !pub.valid?

      as_virtualliver do
        pub=Publication.new(:title => "test4", :doi => "1234", :projects => [Factory(:project)])
        assert !pub.valid?
      end

      #should be allowed for another project, but only that project on its own
      as_not_virtualliver do
        project2=Factory :project
        pub=Publication.new(:title=>"test5",:pubmed_id=>"1234", :projects => [project2])
        assert pub.valid?
        pub=Publication.new(:title=>"test5",:pubmed_id=>"1234", :projects => [project1,project2])
        assert !pub.valid?

        pub=Publication.new(:title=>"test5",:doi=>"1234", :projects => [project2])
        assert pub.valid?
        pub=Publication.new(:title=>"test5",:doi=>"1234", :projects => [project1,project2])
        assert !pub.valid?
      end

      #make sure you can edit yourself!
      p=Factory :publication
      User.with_current_user p.contributor do
        p.save!
        p.abstract="an abstract"
        assert p.valid?
        p.save!
      end
  end

  test "validate uniqueness of title" do
    project1=Factory :project
    pub=Publication.new(:title=>"test1",:pubmed_id=>"1234", :projects => [project1])
    assert pub.valid?
    assert pub.save
    pub=Publication.new(:title=>"test1",:pubmed_id=>"33343", :projects => [project1])
    assert !pub.valid?


    project2=Factory :project
    pub=Publication.new(:title=>"test1",:pubmed_id=>"234", :projects => [project2])
    as_virtualliver do
      assert !pub.valid?
    end
    as_not_virtualliver do
      assert pub.valid?
    end

    #make sure you can edit yourself!
    p=Factory :publication
    User.with_current_user p.contributor do
      p.save!
      p.abstract="an abstract"
      assert p.valid?
      p.save!
    end
  end

  def mock_crossref options
    url= "http://www.crossref.org/openurl/"
    params={}
    params[:format] = "unixref"
    params[:id] = "doi:"+options[:doi]
    params[:pid] = options[:email]
    params[:noredirect] = true
    url = "http://www.crossref.org/openurl/?" + params.to_param
    file=options[:content_file]
    stub_request(:get,url).to_return(:body=>File.new("#{Rails.root}/test/fixtures/files/mocking/#{file}"))

  end

  def mock_pubmed options
    url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    file=options[:content_file]
    stub_request(:post,url).to_return(:body=>File.new("#{Rails.root}/test/fixtures/files/mocking/#{file}"))
  end
  
end
