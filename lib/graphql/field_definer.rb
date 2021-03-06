# Every {Node} class has a {FieldDefiner} instance that
# enables the `field.{something}` API.
#
# When you call `field.{type}({method_name})`, you're creating a {FieldMapping}.
# The {FieldMapping} will expose the value from `method_name` with nodes of type `type`.
class GraphQL::FieldDefiner
  attr_reader :owner_class
  def initialize(owner_class)
    @owner_class = owner_class
  end

  # `method_name` is used as a field type and looked up against {GraphQL::SCHEMA}.
  # `args[0]` is the name for the field of that type.
  def method_missing(method_name, *args, &block)
    field_name = args[0] || method_name
    map_field(field_name, type: method_name, description: args[1])
  end

  private

  def map_field(field_name, type: nil, description: nil)
    field_name = field_name.to_s
    mapping = GraphQL::Field.new(
      name: field_name,
      type: type,
    )
    owner_class.own_fields[field_name] = mapping
  end
end