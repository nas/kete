class TopicType < ActiveRecord::Base
  # dependent topics should be what if a topic_type is destroyed?
  has_many :topics
  has_many :topic_type_to_field_mappings, :dependent => :destroy, :order => 'position'
  # Walter McGinnis (walter@katipo.co.nz), 2006-10-05
  # these association extension maybe able to be cleaned up with modules or something in rails proper down the line
  # code based on work by hasmanythrough.com
  # you have to do the elimination of dupes through the sql
  # otherwise, rails will reorder by topic_type_to_field_mapping.id after the sql has bee run
  has_many :form_fields, :through => :topic_type_to_field_mappings, :source => :extended_field, :select => "distinct topic_type_to_field_mappings.position, extended_fields.*", :order => 'position' do
    def <<(extended_field)
      TopicTypeToFieldMapping.add_as_to("false", self, extended_field)
    end
  end
  has_many :required_form_fields, :through => :topic_type_to_field_mappings, :source => :required_form_field, :select => "distinct topic_type_to_field_mappings.position, extended_fields.*", :conditions => "topic_type_to_field_mappings.required = 'true'", :order => 'position' do
    def <<(required_form_field)
      TopicTypeToFieldMapping.add_as_to("true", self, required_form_field)
    end
  end

  # imports are processes to bring in content to a basket
  # they specify a topic type of thing they are importing
  # or a topic type for the item that relates groups of things
  # that they are importing
  has_many :imports, :dependent => :destroy

  validates_presence_of :name, :description
  validates_uniqueness_of :name, :case_sensitive => false

  # to support inheritance of fields from ancestor topic types
  acts_as_nested_set

  # TODO: globalize stuff, uncomment later
  # translates :name, :description

  # we have a generic topic_type of Topic from which all types inherit their attributes
  # since these default fields reflect the state of the Topic model
  # then we also have ancestor fields for all the topic types above this topic type

  def available_fields
    @available_fields = ExtendedField.find_available_fields(self,'TopicType')
  end
end
