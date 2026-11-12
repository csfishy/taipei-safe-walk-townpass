import com.carrotsearch.hppc.LongLongHashMap;
import com.onthegomap.planetiler.Planetiler;
import com.onthegomap.planetiler.config.Arguments;
import com.protomaps.basemap.Basemap;
import com.protomaps.basemap.feature.CountryCoder;
import com.protomaps.basemap.feature.QrankDb;
import java.nio.file.Path;

/** Inland Taipei extract: all basemap layers from OSM, without global coast/landcover downloads. */
public class TaipeiBasemap {
  public static void main(String[] argv) throws Exception {
    var args = Arguments.fromArgs(argv);
    Planetiler.create(args)
      .addOsmSource("osm", args.inputFile("osm", "Geofabrik Taiwan PBF", Path.of("taiwan-261111.osm.pbf")))
      .setProfile(new Basemap(new QrankDb(new LongLongHashMap()), CountryCoder.fromJarResource(), null, ""))
      .setOutput(Path.of("taipei.mbtiles"))
      .run();
  }
}
