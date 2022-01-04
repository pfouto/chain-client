import java.io.IOException;
import java.nio.charset.Charset;

import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.TimeUnit;

import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.KeeperException;
import org.apache.zookeeper.WatchedEvent;
import org.apache.zookeeper.Watcher;
import org.apache.zookeeper.ZooDefs;
import org.apache.zookeeper.ZooKeeper;
import org.json.simple.JSONObject;
import org.json.simple.JSONValue;

import site.ycsb.ByteIterator;
import site.ycsb.DB;
import site.ycsb.DBException;
import site.ycsb.Status;
import site.ycsb.StringByteIterator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * YCSB binding for <a href="https://zookeeper.apache.org/">ZooKeeper</a>.
 * <p>
 * See {@code zookeeper/README.md} for details.
 */
public class ZKClient extends DB {

    //private static final String CONNECT_STRING = "zookeeper.connectString";
    private static final String DEFAULT_CONNECT_STRING = "127.0.0.1:2181";
    private static final String SESSION_TIMEOUT_PROPERTY = "zookeeper.sessionTimeout";
    private static final long DEFAULT_SESSION_TIMEOUT = TimeUnit.SECONDS.toMillis(200L);
    private static final Charset UTF_8 = StandardCharsets.UTF_8;
    private static final Logger LOG = LoggerFactory.getLogger(ZKClient.class);
    private ZooKeeper zk;
    private Watcher watcher;

    /**
     * converting the key:values map to JSON Strings.
     */
    private static String getJsonStrFromByteMap(Map<String, ByteIterator> map) {
        Map<String, String> stringMap = StringByteIterator.getStringMap(map);
        return JSONValue.toJSONString(stringMap);
    }

    public void init() throws DBException {
        Properties props = getProperties();

       // String connectString = props.getProperty(CONNECT_STRING);
        //if (connectString == null || connectString.length() == 0) {
         //   connectString = DEFAULT_CONNECT_STRING;
        //}

        watcher = null;

        long sessionTimeout;
        String sessionTimeoutString = props.getProperty(SESSION_TIMEOUT_PROPERTY);
        if (sessionTimeoutString != null) {
            sessionTimeout = Integer.parseInt(sessionTimeoutString);
        } else {
            sessionTimeout = DEFAULT_SESSION_TIMEOUT;
        }

        String host = getProperties().getProperty("hosts");
        String[] hosts = host.split(",");
        String myServer = hosts[new Random().nextInt(hosts.length)] + ":2181";
        try {
            zk = new ZooKeeper(myServer, (int) sessionTimeout, new SimpleWatcher());
        } catch (IOException e) {
            throw new DBException("Creating connection failed.");
        }
    }

    public void cleanup() throws DBException {
        try {
            zk.close();
        } catch (InterruptedException e) {
            throw new DBException("Closing connection failed.");
        }
    }

    @Override
    public Status read(String table, String key, Set<String> fields,
                       Map<String, ByteIterator> result) {
        String path = getPath(key);
        try {
            byte[] data = zk.getData(path, watcher, null);
            if (data == null || data.length == 0) {
                return Status.NOT_FOUND;
            }

            deserializeValues(data, fields, result);
            return Status.OK;
        } catch (KeeperException | InterruptedException e) {
            LOG.error("Error when reading a path:{},tableName:{}", path, table, e);
            System.exit(1);
            return Status.ERROR;
        }
    }

    @Override
    public Status insert(String table, String key,
                         Map<String, ByteIterator> values) {
        String path = getPath(key);
        String data = getJsonStrFromByteMap(values);
        try {
            zk.create(path, data.getBytes(UTF_8), ZooDefs.Ids.OPEN_ACL_UNSAFE,
                    CreateMode.PERSISTENT);
            return Status.OK;
        } catch (KeeperException.NodeExistsException e1) {
            return Status.OK;
        } catch (KeeperException | InterruptedException e2) {
            LOG.error("Error when inserting a path:{},tableName:{}", path, table, e2);
            System.exit(1);
            return Status.ERROR;
        }
    }

    @Override
    public Status delete(String table, String key) {

        String path = getPath(key);
        try {
            zk.delete(path, -1);
            return Status.OK;
        } catch (InterruptedException | KeeperException e) {
            LOG.error("Error when deleting a path:{},tableName:{}", path, table, e);
            System.exit(1);
            return Status.ERROR;
        }
    }

    @Override
    public Status update(String table, String key,
                         Map<String, ByteIterator> values) {
        String path = getPath(key);
        try {
            // we have to do a read operation here before setData to meet the YCSB's update semantics:
            // update a single record in the database, adding or replacing the specified fields.

            /*
            byte[] data = zk.getData(path, watcher, null);
            if (data == null || data.length == 0) {
                return Status.NOT_FOUND;
            }
            final Map<String, ByteIterator> result = new HashMap<>();
            deserializeValues(data, null, result);*/
            final Map<String, ByteIterator> result = new HashMap<>(values);
            // update
            zk.setData(path, getJsonStrFromByteMap(result).getBytes(UTF_8), -1);
            return Status.OK;
        } catch (KeeperException | InterruptedException e) {
            LOG.error("Error when updating a path:{},tableName:{}", path, table, e);
            System.exit(1);
            return Status.ERROR;
        }
    }

    @Override
    public Status scan(String table, String startkey, int recordcount,
                       Set<String> fields, Vector<HashMap<String, ByteIterator>> result) {
        return Status.NOT_IMPLEMENTED;
    }

    private String getPath(String key) {
        return key.startsWith("/") ? key : "/" + key;
    }

    private Map<String, ByteIterator> deserializeValues(final byte[] data, final Set<String> fields,
                                                        final Map<String, ByteIterator> result) {
        JSONObject jsonObject = (JSONObject) JSONValue.parse(new String(data, UTF_8));
        Iterator<String> iterator = jsonObject.keySet().iterator();
        while (iterator.hasNext()) {
            String field = iterator.next();
            String value = jsonObject.get(field).toString();
            if (fields == null || fields.contains(field)) {
                result.put(field, new StringByteIterator(value));
            }
        }
        return result;
    }

    private static class SimpleWatcher implements Watcher {

        public void process(WatchedEvent e) {
            if (e.getType() == Event.EventType.None) {
                return;
            }

            if (e.getState() == Event.KeeperState.SyncConnected) {
                //do nothing
            }
        }
    }
}
