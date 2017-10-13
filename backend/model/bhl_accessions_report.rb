class BhlAccessionsReport < AbstractReport
  
  register_report({
                    :uri_suffix => "bhl_accessions_report",
                    :description => "Bentley Historical Library Accessions Report",
                    :params => [["from", Date, "The start of report range"],
                                ["to", Date, "The end of report range"],
                                ["Additional Parameters", "accessionsparams", "Additional Accession parameters"]]
                  })

  
  include JSONModel

  attr_reader :processing_status, :processing_priority, :classification, :donor_uri, :donor_type, :donor_id

  def initialize(params, job)
    super
    if ASUtils.present?(params['processing_status'])
      @processing_status = params["processing_status"]
    end

    if ASUtils.present?(params['processing_priority'])
      @processing_priority = params["processing_priority"]
    end

    if ASUtils.present?(params['classification'])
      @classification = params["classification"]
    end

    if ASUtils.present?(params["from"])
      from = params["from"]
    else
      from = Time.new(1800, 01, 01).to_s
    end

    if ASUtils.present?(params["to"])
      to = params["to"]
    else
      to = Time.now.to_s
    end

    @from = DateTime.parse(from).to_time.strftime("%Y-%m-%d %H:%M:%S")
    @to = DateTime.parse(to).to_time.strftime("%Y-%m-%d %H:%M:%S")

    if ASUtils.present?(params["donor"])
      @donor_uri = params["donor"]["ref"]
      if donor_uri.include?("people")
        @donor_type = "agent_person"
      elsif donor_uri.include?("families")
        @donor_type = "agent_family"
      elsif donor_uri.include?("corporate_entities")
        @donor_type = "agent_corporate_entity"
      end
      @donor_id = JSONModel(donor_type).id_for(donor_uri)
    end

    # TO DO
    # extent: calculate a total
  end

  def title
    "Bentley Historical Library Accessions Report"
  end

  def headers
    ['identifier', 'donor_name', 'donor_number', 'accession_date', 'content_description', 'processing_status', 'processing_priority', 'classifications', 'extent_number_type', 'location']
  end

  def processor
    {
      'identifier' => proc {|record| ASUtils.json_parse(record[:identifier] || "[]").compact.join("-")}
    }
  end

  def scope_by_repo_id(dataset)
    # repo scope is applied in the query below
    dataset
  end

  def query(db)
    source_enum_id = db[:enumeration].filter(:name=>'linked_agent_role').join(:enumeration_value, :enumeration_id => :id).where(:value => 'source').all[0][:id]

    dataset = db[:accession].where(:accession_date => (@from..@to)).
    left_outer_join(:linked_agents_rlshp, [[:accession_id, Sequel.qualify(:accession, :id)], [:role_id, source_enum_id]]).
    left_outer_join(:collection_management, :accession_id => Sequel.qualify(:accession, :id)).
    join(:enumeration,
        {
          :name => "collection_management_processing_status"
        },
        {
          :table_alias => :enum_processing_status
        }).
    join(:enumeration,
        {
         :name => 'collection_management_processing_priority'
        },
        {
         :table_alias => :enum_processing_priority
        }).
    left_outer_join(:enumeration_value,
        {
          Sequel.qualify(:enumvals_processing_status, :enumeration_id) => Sequel.qualify(:enum_processing_status, :id),
          Sequel.qualify(:collection_management, :processing_status_id) => Sequel.qualify(:enumvals_processing_status, :id),
        },
        {
          :table_alias => :enumvals_processing_status
        }).
    left_outer_join(:enumeration_value,
        {
          Sequel.qualify(:enumvals_processing_priority, :enumeration_id) =>  Sequel.qualify(:enum_processing_priority, :id),
          Sequel.qualify(:collection_management, :processing_priority_id) => Sequel.qualify(:enumvals_processing_priority, :id),
        },
        {
         :table_alias => :enumvals_processing_priority
        }).
    left_outer_join(:user_defined, :accession_id => Sequel.qualify(:accession, :id)).
    select(
      Sequel.qualify(:accession, :id).as(:accession_id),
      Sequel.qualify(:accession, :accession_date).as(:accession_date),
      Sequel.qualify(:accession, :identifier),
      Sequel.qualify(:accession, :content_description),
      Sequel.as(Sequel.lit('GetAccessionLocationUserDefined(accession.id)'), :location),
      Sequel.as(Sequel.lit('GetAccessionProcessingStatus(accession.id)'), :processing_status),
      Sequel.as(Sequel.lit('GetAccessionProcessingPriority(accession.id)'), :processing_priority),
      Sequel.as(Sequel.lit('GetAccessionClassificationsUserDefined(accession.id)'), :classifications),
      Sequel.as(Sequel.lit('GetAccessionExtentNumberType(accession.id)'), :extent_number_type),
      Sequel.as(Sequel.lit('GetAccessionSourceName(accession.id)'), :donor_name),
      Sequel.as(Sequel.lit('GetAccessionDonorNumbers(accession.id)'), :donor_number),
      ).group(Sequel.qualify(:accession, :id))

    dataset = dataset.where(Sequel.qualify(:accession, :repo_id) => @repo_id)

    if processing_status
      if processing_status == "No Defined Value"
        dataset = dataset.where(Sequel.qualify(:enumvals_processing_status, :value) => nil)
      elsif processing_status == "Any Defined Value"
        dataset = dataset.exclude(Sequel.qualify(:enumvals_processing_status, :value) => nil)
      else
        dataset = dataset.where(Sequel.qualify(:enumvals_processing_status, :value) => @processing_status)
      end
    end

    if processing_priority
      if processing_priority == "No Defined Value"
        dataset = dataset.where(Sequel.qualify(:enumvals_processing_priority, :value) => nil)
      elsif processing_priority == "Any Defined Value"
        dataset = dataset.exclude(Sequel.qualify(:enumvals_processing_priority, :value) => nil)
      else
        dataset = dataset.where(Sequel.qualify(:enumvals_processing_priority, :value) => @processing_priority)
      end
    end

    if classification
      #where{(price - 100 > 200) | (price / 100 >= 200)}
      dataset = dataset.where(Sequel.lit('GetEnumValue(user_defined.enum_1_id)') => @classification).or(Sequel.lit('GetEnumValue(user_defined.enum_2_id)') => @classification).or(Sequel.lit('GetEnumValue(user_defined.enum_3_id)') => @classification)
    end

    if donor_uri
      dataset = dataset.where(Sequel.qualify(:linked_agents_rlshp, :"#{@donor_type}_id") => @donor_id)
    end

    dataset
  end

end
