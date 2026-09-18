// Read-only discovery through browser-use's js() helper. No tool is executed.
(async () => {
  const context = document.modelContext;
  const testing = navigator.modelContextTesting;
  let api = null;
  let tools = [];
  if (typeof context?.getTools === 'function') {
    api = 'document.modelContext';
    tools = await context.getTools();
  } else if (typeof testing?.listTools === 'function') {
    api = 'navigator.modelContextTesting';
    tools = await testing.listTools();
  }
  return {
    origin: location.origin,
    supported: api !== null,
    api,
    tools: tools.map(({name, title, description, inputSchema, annotations, origin}) =>
      ({name, title, description, inputSchema, annotations, origin})),
  };
})()
