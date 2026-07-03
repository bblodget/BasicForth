/* BasicForth — DRM struct offset / ioctl-number reference (dev aid, not built
 * into BasicForth). Prints the field offsets, struct sizes, and ioctl numbers
 * that drm.fs hard-codes, straight from the kernel uapi headers, so they can be
 * verified rather than guessed.  Build & run:  cc -o drmoff tools/drmoff.c && ./drmoff
 * SPDX-License-Identifier: GPL-2.0-only */
#include <stdio.h>
#include <stddef.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>
#define O(s,f) printf("  %-22s %2zu\n", #f, offsetof(struct s, f))
#define SZ(s)  printf("struct %-22s size=%zu\n", #s, sizeof(struct s))
int main(void){
  printf("-- ioctl numbers --\n");
  printf("GETRES=0x%lx GETCONN=0x%lx GETENC=0x%lx\n",
    (unsigned long)DRM_IOCTL_MODE_GETRESOURCES,(unsigned long)DRM_IOCTL_MODE_GETCONNECTOR,(unsigned long)DRM_IOCTL_MODE_GETENCODER);
  printf("CREATE_DUMB=0x%lx MAP_DUMB=0x%lx ADDFB=0x%lx SETCRTC=0x%lx\n",
    (unsigned long)DRM_IOCTL_MODE_CREATE_DUMB,(unsigned long)DRM_IOCTL_MODE_MAP_DUMB,
    (unsigned long)DRM_IOCTL_MODE_ADDFB,(unsigned long)DRM_IOCTL_MODE_SETCRTC);
  printf("SET_MASTER=0x%lx DROP_MASTER=0x%lx\n",(unsigned long)DRM_IOCTL_SET_MASTER,(unsigned long)DRM_IOCTL_DROP_MASTER);
  printf("PAGE_FLIP=0x%lx  PAGE_FLIP_EVENT=0x%x\n",
    (unsigned long)DRM_IOCTL_MODE_PAGE_FLIP,(unsigned)DRM_MODE_PAGE_FLIP_EVENT);
  printf("\n-- struct sizes & offsets --\n");
  SZ(drm_mode_card_res);
  O(drm_mode_card_res, crtc_id_ptr); O(drm_mode_card_res, connector_id_ptr);
  O(drm_mode_card_res, count_crtcs); O(drm_mode_card_res, count_connectors);
  SZ(drm_mode_get_connector);
  O(drm_mode_get_connector, modes_ptr); O(drm_mode_get_connector, count_modes);
  O(drm_mode_get_connector, encoder_id); O(drm_mode_get_connector, connector_id);
  O(drm_mode_get_connector, connection);
  SZ(drm_mode_get_encoder);
  O(drm_mode_get_encoder, encoder_id); O(drm_mode_get_encoder, crtc_id);
  SZ(drm_mode_modeinfo);
  O(drm_mode_modeinfo, hdisplay); O(drm_mode_modeinfo, vdisplay);
  SZ(drm_mode_create_dumb);
  O(drm_mode_create_dumb, height); O(drm_mode_create_dumb, width);
  O(drm_mode_create_dumb, bpp); O(drm_mode_create_dumb, handle);
  O(drm_mode_create_dumb, pitch); O(drm_mode_create_dumb, size);
  SZ(drm_mode_map_dumb);
  O(drm_mode_map_dumb, handle); O(drm_mode_map_dumb, offset);
  SZ(drm_mode_fb_cmd);
  O(drm_mode_fb_cmd, fb_id); O(drm_mode_fb_cmd, width); O(drm_mode_fb_cmd, height);
  O(drm_mode_fb_cmd, pitch); O(drm_mode_fb_cmd, bpp); O(drm_mode_fb_cmd, depth);
  O(drm_mode_fb_cmd, handle);
  SZ(drm_mode_crtc);
  O(drm_mode_crtc, set_connectors_ptr); O(drm_mode_crtc, count_connectors);
  O(drm_mode_crtc, crtc_id); O(drm_mode_crtc, fb_id); O(drm_mode_crtc, mode_valid);
  O(drm_mode_crtc, mode);
  SZ(drm_mode_crtc_page_flip);
  O(drm_mode_crtc_page_flip, crtc_id); O(drm_mode_crtc_page_flip, fb_id);
  O(drm_mode_crtc_page_flip, flags); O(drm_mode_crtc_page_flip, user_data);
  SZ(drm_event); O(drm_event, type); O(drm_event, length);
  SZ(drm_event_vblank); O(drm_event_vblank, user_data); O(drm_event_vblank, sequence);
  return 0;
}
