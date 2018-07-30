defprotocol FDB.Directory do
  def layer(directory)

  def path(directory)

  def create_or_open(directory, tr, path, options \\ %{})

  def open(directory, tr, path, options \\ %{})

  def create(directory, tr, path, options \\ %{})

  def move_to(directory, tr, new_absolute_path)

  def move(directory, tr, old_path, new_path)

  def remove(directory, tr, path \\ [])

  def remove_if_exists(directory, tr, path \\ [])

  def exists?(directory, tr, path \\ [])

  def list(directory, tr, path \\ [])

  def get_layer_for_path(directory, path)
end
