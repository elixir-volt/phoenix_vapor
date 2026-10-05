defmodule VaporDemoWeb.Workspace.ContactsLive do
  @moduledoc """
  The workspace's contacts. Search, sort, selection and the copied-email
  notice are the browser's; deleting goes through the server, and every open
  page sees it.
  """

  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "Contacts.vue"

  alias VaporDemo.Contacts

  def mount(_params, _session, socket) do
    if connected?(socket), do: Contacts.subscribe()
    {:ok, assign(socket, page_title: "Contacts", contacts: Contacts.list())}
  end

  def handle_event("deleteContacts", %{"ids" => ids}, socket) when is_list(ids) do
    {:noreply, assign(socket, contacts: Contacts.delete(ids))}
  end

  def handle_info({:contacts, contacts}, socket),
    do: {:noreply, assign(socket, contacts: contacts)}
end
