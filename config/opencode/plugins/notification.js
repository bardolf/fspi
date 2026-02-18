export const NotificationPlugin = async ({ $, client }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        const session = await client.session.get({ path: { id: event.properties.sessionID } })
        // Only notify for main sessions (no parent)
        if (!session.data.parentID) {
          await $`notify-send -i utilities-terminal "OpenCode" "Task completed!"`
        }
      }
    },
  }
}
