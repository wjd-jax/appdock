import * as ActionCable from "@rails/actioncable"
import { AppDock } from "../controllers/appdock"

if (AppDock.isDevelopment) {
  ActionCable.logger.enabled = true
}
